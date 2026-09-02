defmodule Liminal.Links.JanitorTest do
  # GenServer sweeps use the database outside the test process; keep this module
  # serial and grant the janitor access to the SQL sandbox connection.
  use Liminal.DataCase, async: false

  alias Liminal.Links
  alias Liminal.Links.Janitor

  setup do
    user = Liminal.AccountsFixtures.user_fixture()
    scope = Liminal.Accounts.Scope.for_user(user)
    {:ok, scope: scope}
  end

  describe "sweep" do
    test "removes expired link_tags and orphaned links", %{scope: scope} do
      # Create a link with a tag that has a short expiry
      tag = insert_tag(scope, %{expires_in_days: 1})
      {:ok, link} = Links.create_link(scope, %{url: "https://example.com"}, [tag.id])

      # Refetch link with preloaded link_tags
      link = Links.get_link!(scope, link.id)
      link_tags_before = link.link_tags
      assert length(link_tags_before) == 1

      # Manually update the link_tag to be expired (in the past)
      link_tag_id = hd(link_tags_before).id

      Repo.update_all(
        from(lt in Liminal.Links.LinkTag, where: lt.id == ^link_tag_id),
        set: [expires_at: DateTime.utc_now(:second) |> DateTime.add(-1, :second)]
      )

      janitor_pid = start_janitor!()

      # Trigger the sweep manually
      send(janitor_pid, :sweep)

      # Sync with the process to ensure it has handled the message
      _ = :sys.get_state(janitor_pid)

      # Assert link and link_tag are deleted
      assert_raise Ecto.NoResultsError, fn ->
        Links.get_link!(scope, link.id)
      end
    end
  end

  describe "sweep with paused expiries" do
    test "leaves an overdue link alone while its owner is paused", %{scope: scope} do
      tag = insert_tag(scope, %{expires_in_days: 1})
      {:ok, link} = Links.create_link(scope, %{url: "https://example.com"}, [tag.id])
      expire_link_tags(link)

      {:ok, _paused} = Links.pause_expiries(scope, 7)

      janitor_pid = start_janitor!()
      send(janitor_pid, :sweep)
      _ = :sys.get_state(janitor_pid)

      assert Links.get_link!(scope, link.id)
    end

    test "settles a pause that has run out", %{scope: scope} do
      {:ok, paused} = Links.pause_expiries(scope, 7)
      _lapsed = Liminal.LinksFixtures.lapse_expiry_pause(paused)

      janitor_pid = start_janitor!()
      send(janitor_pid, :sweep)
      _ = :sys.get_state(janitor_pid)

      settled = Liminal.Accounts.get_user!(scope.user.id)
      assert is_nil(settled.expiry_paused_at)
      assert is_nil(settled.expiry_paused_until)
    end
  end

  describe "sweep with unindexed links" do
    test "sweep completes without error when unindexed links exist", %{scope: scope} do
      tag = insert_tag(scope, %{expires_in_days: 30})
      {:ok, link} = Links.create_link(scope, %{url: "https://example.com"}, [tag.id])

      # Back-date to make it eligible for re-indexing
      past = DateTime.utc_now(:second) |> DateTime.add(-2, :minute)

      Repo.update_all(
        from(l in Liminal.Links.Link, where: l.id == ^link.id),
        set: [inserted_at: past]
      )

      # Verify the link is unindexed and eligible
      assert [unindexed] = Links.list_index_retry_candidates()
      assert unindexed.id == link.id

      # Sweep completes without crashing (indexer tasks are gated by start_indexer config)
      janitor_pid = start_janitor!()
      send(janitor_pid, :sweep)
      _ = :sys.get_state(janitor_pid)

      # Link still exists, still unindexed (no tasks spawned in test)
      refetched = Links.get_link!(scope, link.id)
      assert is_nil(refetched.indexed_at)
    end
  end

  defp start_janitor! do
    janitor_pid = start_supervised!({Janitor, skip_initial_sweep: true})
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), janitor_pid)
    janitor_pid
  end

  defp expire_link_tags(link) do
    Repo.update_all(
      from(lt in Liminal.Links.LinkTag, where: lt.link_id == ^link.id),
      set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second)]
    )
  end

  defp insert_tag(scope, attrs) do
    default_attrs = %{
      name: "Test tag #{Ecto.UUID.generate()}",
      expires_in_days: nil
    }

    {:ok, tag} = Links.create_tag(scope, Map.merge(default_attrs, attrs))
    tag
  end
end
