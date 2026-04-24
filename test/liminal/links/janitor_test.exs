defmodule Liminal.Links.JanitorTest do
  use Liminal.DataCase

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

      # Start the janitor under test supervision
      janitor_pid = start_supervised!(Janitor)

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

  defp insert_tag(scope, attrs) do
    default_attrs = %{
      name: "Test tag #{Ecto.UUID.generate()}",
      expires_in_days: nil
    }

    {:ok, tag} = Links.create_tag(scope, Map.merge(default_attrs, attrs))
    tag
  end
end
