defmodule Liminal.Links.ReindexTest do
  use Liminal.DataCase, async: false

  import Ecto.Query

  alias Liminal.Accounts.Scope
  alias Liminal.Links
  alias Liminal.Links.{Link, Reindex}

  setup do
    user = Liminal.AccountsFixtures.user_fixture()
    scope = Scope.for_user(user)
    reindex_pid = start_reindex!()

    on_exit(fn ->
      if Process.alive?(reindex_pid), do: GenServer.stop(reindex_pid, :normal, 5_000)
    end)

    {:ok, scope: scope, reindex_pid: reindex_pid}
  end

  describe "start_job/2" do
    test "queues only failed links for instance :failed scope", %{scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)
      {:ok, failed} = Links.create_link(scope, %{url: "https://failed.example.com"}, [tag.id])
      {:ok, indexed} = Links.create_link(scope, %{url: "https://indexed.example.com"}, [tag.id])

      now = DateTime.utc_now(:second)

      Repo.update_all(from(l in Link, where: l.id == ^failed.id),
        set: [index_attempt_count: 2, index_last_attempted_at: now]
      )

      Repo.update_all(from(l in Link, where: l.id == ^indexed.id),
        set: [indexed_at: now]
      )

      assert {:ok, %{active: true, scope: {:instance, :failed}, total: 1}} =
               Reindex.start_job({:instance, :failed})
    end

    test "queues all links for a user scope", %{scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)

      {:ok, _} = Links.create_link(scope, %{url: "https://one.example.com"}, [tag.id])
      {:ok, _} = Links.create_link(scope, %{url: "https://two.example.com"}, [tag.id])

      assert {:ok, %{active: true, scope: {:user, user_id, :all}, total: 2}} =
               Reindex.start_job({:user, scope.user.id, :all})

      assert user_id == scope.user.id
    end

    test "processes a single link immediately", %{scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)
      {:ok, link} = Links.create_link(scope, %{url: "https://solo.example.com"}, [tag.id])
      now = DateTime.utc_now(:second)

      Repo.update_all(from(l in Link, where: l.id == ^link.id),
        set: [index_attempt_count: 2, index_last_attempted_at: now, index_gave_up_at: now]
      )

      assert {:ok, %{active: false, last_job: %{outcome: :completed, total: 1}}} =
               Reindex.start_job({:link, link.id})

      refetched = Links.get_link!(scope, link.id)
      assert refetched.index_attempt_count == 0
      assert is_nil(refetched.index_gave_up_at)
    end

    test "returns error when a job is already running", %{scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)
      {:ok, _} = Links.create_link(scope, %{url: "https://busy-one.example.com"}, [tag.id])
      {:ok, _} = Links.create_link(scope, %{url: "https://busy-two.example.com"}, [tag.id])

      assert {:ok, %{active: true}} = Reindex.start_job({:instance, :all})
      assert {:error, :already_running} = Reindex.start_job({:instance, :failed})
      assert Reindex.active?()
    end
  end

  describe "cancel/0" do
    test "stops a running job", %{scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)
      {:ok, _} = Links.create_link(scope, %{url: "https://cancel-one.example.com"}, [tag.id])
      {:ok, _} = Links.create_link(scope, %{url: "https://cancel-two.example.com"}, [tag.id])

      assert {:ok, %{active: true}} = Reindex.start_job({:instance, :all})
      assert :ok = Reindex.cancel()
      assert %{active: false, last_job: %{outcome: :cancelled}} = Reindex.status()
    end
  end

  describe "list_reindex_link_ids/1" do
    test ":failed excludes never-attempted unindexed links", %{scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)
      {:ok, fresh} = Links.create_link(scope, %{url: "https://fresh.example.com"}, [tag.id])
      {:ok, failed} = Links.create_link(scope, %{url: "https://retry.example.com"}, [tag.id])

      now = DateTime.utc_now(:second)

      Repo.update_all(from(l in Link, where: l.id == ^failed.id),
        set: [index_attempt_count: 1, index_last_attempted_at: now]
      )

      ids = Links.list_reindex_link_ids({:instance, :failed})

      assert failed.id in ids
      refute fresh.id in ids
    end
  end

  describe "retry_indexing/2" do
    test "retry_indexing/2 resets retry state for gave-up link", %{scope: scope} do
      link = Liminal.LinksFixtures.link_fixture(scope, %{title: nil})
      now = DateTime.utc_now(:second)

      Repo.update_all(from(l in Link, where: l.id == ^link.id),
        set: [
          index_attempt_count: 10,
          index_gave_up_at: now,
          index_last_attempted_at: now
        ]
      )

      link = Links.get_link!(scope, link.id)

      assert {:ok, updated} = Links.retry_indexing(scope, link)
      assert updated.index_attempt_count == 0
      assert is_nil(updated.index_gave_up_at)
      assert is_nil(updated.index_next_attempt_at)
    end

    test "returns :reindex_busy when another job is active", %{scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)
      {:ok, link1} = Links.create_link(scope, %{url: "https://one.example.com"}, [tag.id])
      {:ok, link2} = Links.create_link(scope, %{url: "https://two.example.com"}, [tag.id])

      assert {:ok, %{active: true}} = Reindex.start_job({:instance, :all})
      assert {:error, :reindex_busy} = Links.retry_indexing(scope, link2)

      Reindex.cancel()
      assert {:ok, _} = Links.retry_indexing(scope, link1)
    end
  end

  defp start_reindex! do
    Application.put_env(:liminal, Liminal.Links.Reindex, batch_size: 10, interval_ms: 50)

    reindex_pid = start_supervised!({Reindex, []})
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), reindex_pid)
    reindex_pid
  end
end
