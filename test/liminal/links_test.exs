defmodule Liminal.LinksTest do
  use Liminal.DataCase

  alias Liminal.Links

  import Liminal.AccountsFixtures
  import Liminal.LinksFixtures

  describe "list_tags/1" do
    test "returns tags scoped to the user" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()

      tag = tag_fixture(scope_a, %{name: "my tag"})
      _other = tag_fixture(scope_b, %{name: "other tag"})

      tags_a = Links.list_tags(scope_a)
      assert Enum.any?(tags_a, fn t -> t.id == tag.id end)
      refute Enum.any?(Links.list_tags(scope_b), fn t -> t.id == tag.id end)
    end

    test "returns only default tags for a new user" do
      scope = user_scope_fixture()
      tags = Links.list_tags(scope)
      assert length(tags) == 3
    end
  end

  describe "create_tag/2" do
    test "creates a tag with valid attrs" do
      scope = user_scope_fixture()

      assert {:ok, tag} =
               Links.create_tag(scope, %{name: "bookmarks", expires_in_days: 7})

      assert tag.name == "bookmarks"
      assert tag.expires_in_days == 7
      assert tag.user_id == scope.user.id
    end

    test "returns error changeset with blank name" do
      scope = user_scope_fixture()

      assert {:error, changeset} = Links.create_tag(scope, %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error changeset for duplicate name for the same user" do
      scope = user_scope_fixture()
      tag_fixture(scope, %{name: "dupe"})

      assert {:error, changeset} = Links.create_tag(scope, %{name: "dupe"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update_tag/3" do
    test "updates name and expires_in_days" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope, %{name: "old name", expires_in_days: 10})

      assert {:ok, updated} =
               Links.update_tag(scope, tag, %{name: "new name", expires_in_days: 60})

      assert updated.name == "new name"
      assert updated.expires_in_days == 60
    end
  end

  describe "delete_tag/2" do
    test "removes the tag" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope)

      before_count = length(Links.list_tags(scope))
      assert {:ok, _deleted} = Links.delete_tag(scope, tag)
      assert length(Links.list_tags(scope)) == before_count - 1
    end
  end

  describe "list_links/2" do
    test "returns links scoped to the user with preloaded tags" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()

      link = link_fixture(scope_a)
      _other = link_fixture(scope_b)

      assert [fetched] = Links.list_links(scope_a)
      assert fetched.id == link.id
      assert Ecto.assoc_loaded?(fetched.link_tags)
    end
  end

  describe "create_link/3" do
    test "creates a link with valid attrs and tags" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope, %{expires_in_days: 14})

      assert {:ok, link} =
               Links.create_link(scope, %{url: "https://example.com", title: "Example"}, [
                 tag.id
               ])

      assert link.url == "https://example.com"
      assert link.title == "Example"
      assert link.user_id == scope.user.id

      refetched = Links.get_link!(scope, link.id)
      assert length(refetched.link_tags) == 1
      [lt] = refetched.link_tags
      assert lt.tag_id == tag.id
      assert lt.expires_at != nil
    end

    test "returns error changeset with blank url" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope)

      assert {:error, changeset} = Links.create_link(scope, %{url: ""}, [tag.id])
      assert %{url: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns {:error, :no_tags} with empty tag list" do
      scope = user_scope_fixture()

      assert {:error, :no_tags} =
               Links.create_link(scope, %{url: "https://example.com"}, [])
    end

    test "returns {:error, :no_tags} without tag_ids (2-arity)" do
      scope = user_scope_fixture()

      assert {:error, :no_tags} =
               Links.create_link(scope, %{url: "https://example.com"})
    end

    test "returns {:error, :invalid_tags} when tag IDs don't all resolve" do
      scope = user_scope_fixture()
      valid_tag = tag_fixture(scope)
      bogus_id = Ecto.UUID.generate()

      assert {:error, :invalid_tags} =
               Links.create_link(scope, %{url: "https://example.com"}, [
                 valid_tag.id,
                 bogus_id
               ])

      # No link should have been created
      assert [] = Links.list_links(scope, filter: :all)
    end

    test "returns {:error, :invalid_tags} when using another user's tag" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()
      other_tag = tag_fixture(scope_b)

      assert {:error, :invalid_tags} =
               Links.create_link(scope_a, %{url: "https://example.com"}, [other_tag.id])
    end

    test "broadcasts {:link_created, link} on success" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope)

      Links.subscribe_links(scope)
      {:ok, link} = Links.create_link(scope, %{url: "https://broadcast.com"}, [tag.id])

      assert_receive {:link_created, broadcast_link}
      assert broadcast_link.id == link.id
      assert Ecto.assoc_loaded?(broadcast_link.link_tags)
    end

    test "creates link_tags with correct expires_at" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope, %{expires_in_days: 7})

      {:ok, link} =
        Links.create_link(scope, %{url: "https://example.com"}, [tag.id])

      refetched = Links.get_link!(scope, link.id)
      [lt] = refetched.link_tags

      expected_approx = DateTime.add(DateTime.utc_now(:second), 7, :day)
      diff = DateTime.diff(lt.expires_at, expected_approx, :second) |> abs()
      # Allow up to 5 seconds of clock drift
      assert diff < 5
    end
  end

  describe "update_link/3" do
    test "updates the title" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: "Old Title"})

      assert {:ok, updated} = Links.update_link(scope, link, %{title: "New Title"})
      assert updated.title == "New Title"
    end

    test "broadcasts {:link_updated, link} on success" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: "Old"})

      Links.subscribe_links(scope)
      {:ok, _} = Links.update_link(scope, link, %{title: "New"})

      assert_receive {:link_updated, broadcast_link}
      assert broadcast_link.title == "New"
      assert Ecto.assoc_loaded?(broadcast_link.link_tags)
    end
  end

  describe "delete_link/2" do
    test "removes the link" do
      scope = user_scope_fixture()
      link = link_fixture(scope)

      assert {:ok, _deleted} = Links.delete_link(scope, link)
      assert [] = Links.list_links(scope, filter: :all)
    end

    test "broadcasts {:link_deleted, link_id} on success" do
      scope = user_scope_fixture()
      link = link_fixture(scope)

      Links.subscribe_links(scope)
      {:ok, _} = Links.delete_link(scope, link)

      assert_receive {:link_deleted, link_id}
      assert link_id == link.id
    end
  end

  describe "mark_viewed/2" do
    test "sets viewed_at timestamp" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      assert is_nil(link.viewed_at)

      assert {:ok, _updated} = Links.mark_viewed(scope, link)

      refetched = Links.get_link!(scope, link.id)
      assert refetched.viewed_at != nil
    end

    test "broadcasts {:link_updated, link} with viewed_at set" do
      scope = user_scope_fixture()
      link = link_fixture(scope)

      Links.subscribe_links(scope)
      {:ok, _} = Links.mark_viewed(scope, link)

      assert_receive {:link_updated, broadcast_link}
      assert broadcast_link.viewed_at != nil
    end
  end

  describe "mark_unviewed/2" do
    test "clears viewed_at to nil" do
      scope = user_scope_fixture()
      link = link_fixture(scope)

      {:ok, viewed_link} = Links.mark_viewed(scope, link)
      assert viewed_link.viewed_at != nil

      assert {:ok, _updated} = Links.mark_unviewed(scope, viewed_link)

      refetched = Links.get_link!(scope, link.id)
      assert is_nil(refetched.viewed_at)
    end

    test "broadcasts {:link_updated, link} with viewed_at nil" do
      scope = user_scope_fixture()
      link = link_fixture(scope)

      {:ok, viewed_link} = Links.mark_viewed(scope, link)
      Links.subscribe_links(scope)
      {:ok, _} = Links.mark_unviewed(scope, viewed_link)

      assert_receive {:link_updated, broadcast_link}
      assert is_nil(broadcast_link.viewed_at)
    end
  end

  describe "tag_link/3" do
    test "creates association and sets expires_at based on tag.expires_in_days" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      tag = tag_fixture(scope, %{expires_in_days: 14})

      assert {:ok, _link_tag} = Links.tag_link(scope, link, tag)

      refetched = Links.get_link!(scope, link.id)

      assert Enum.any?(refetched.link_tags, fn lt ->
               lt.tag.id == tag.id and lt.expires_at != nil
             end)
    end

    test "is idempotent — tagging twice does not error" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      tag = tag_fixture(scope)

      assert {:ok, _} = Links.tag_link(scope, link, tag)
      assert {:ok, _} = Links.tag_link(scope, link, tag)
    end

    test "broadcasts {:link_updated, link} with new tag" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      tag = tag_fixture(scope)

      Links.subscribe_links(scope)
      {:ok, _} = Links.tag_link(scope, link, tag)

      assert_receive {:link_updated, broadcast_link}
      assert Enum.any?(broadcast_link.link_tags, fn lt -> lt.tag_id == tag.id end)
    end
  end

  describe "untag_link/1" do
    test "removes the link_tag by ID" do
      scope = user_scope_fixture()
      tag1 = tag_fixture(scope)
      tag2 = tag_fixture(scope)
      link = link_fixture(scope, %{tag_ids: [tag1.id, tag2.id]})

      refetched = Links.get_link!(scope, link.id)
      target = Enum.find(refetched.link_tags, &(&1.tag_id == tag1.id))

      assert :ok = Links.untag_link(target.id)

      refetched = Links.get_link!(scope, link.id)
      assert length(refetched.link_tags) == 1
    end

    test "is idempotent — calling twice does not error" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope)
      link = link_fixture(scope, %{tag_ids: [tag.id]})

      refetched = Links.get_link!(scope, link.id)
      [lt] = refetched.link_tags

      assert :ok = Links.untag_link(lt.id)
      assert :ok = Links.untag_link(lt.id)
    end
  end

  describe "cleanup_link/3" do
    test "removes the association and returns {:ok, :tag_removed}" do
      scope = user_scope_fixture()
      tag1 = tag_fixture(scope)
      tag2 = tag_fixture(scope)
      link = link_fixture(scope, %{tag_ids: [tag1.id, tag2.id]})

      assert {:ok, :tag_removed} = Links.cleanup_link(scope, link, tag1)

      refetched = Links.get_link!(scope, link.id)
      assert length(refetched.link_tags) == 1
    end

    test "deletes the link when removing last tag and returns {:ok, :link_deleted}" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope)
      link = link_fixture(scope, %{tag_ids: [tag.id]})

      assert {:ok, :link_deleted} = Links.cleanup_link(scope, link, tag)

      assert [] = Links.list_links(scope, filter: :all)
    end

    test "is idempotent — returns {:ok, :tag_removed} if already untagged" do
      scope = user_scope_fixture()
      tag1 = tag_fixture(scope)
      tag2 = tag_fixture(scope)
      link = link_fixture(scope, %{tag_ids: [tag1.id, tag2.id]})

      assert {:ok, :tag_removed} = Links.cleanup_link(scope, link, tag1)
      assert {:ok, :tag_removed} = Links.cleanup_link(scope, link, tag1)
    end
  end

  describe "cleanup_link/1" do
    test "removes the targeted link_tag and checks orphan" do
      scope = user_scope_fixture()
      tag1 = tag_fixture(scope)
      tag2 = tag_fixture(scope)
      link = link_fixture(scope, %{tag_ids: [tag1.id, tag2.id]})

      refetched = Links.get_link!(scope, link.id)
      target = Enum.find(refetched.link_tags, &(&1.tag_id == tag1.id))

      assert {:ok, :tag_removed} = Links.cleanup_link(target.id)

      refetched = Links.get_link!(scope, link.id)
      assert length(refetched.link_tags) == 1
    end

    test "deletes the link when it becomes orphaned" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope)
      link = link_fixture(scope, %{tag_ids: [tag.id]})

      refetched = Links.get_link!(scope, link.id)
      [lt] = refetched.link_tags

      assert {:ok, :link_deleted} = Links.cleanup_link(lt.id)

      assert [] = Links.list_links(scope, filter: :all)
    end

    test "returns {:ok, :tag_removed} for a non-existent ID" do
      assert {:ok, :tag_removed} = Links.cleanup_link(Ecto.UUID.generate())
    end

    test "broadcasts {:link_deleted, link_id} when link becomes orphaned" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope)
      link = link_fixture(scope, %{tag_ids: [tag.id]})

      Links.subscribe_links(scope)
      refetched = Links.get_link!(scope, link.id)
      [lt] = refetched.link_tags

      assert {:ok, :link_deleted} = Links.cleanup_link(lt.id)
      assert_receive {:link_deleted, link_id}
      assert link_id == link.id
    end

    test "broadcasts {:link_updated, link} when tags remain" do
      scope = user_scope_fixture()
      tag1 = tag_fixture(scope)
      tag2 = tag_fixture(scope)
      link = link_fixture(scope, %{tag_ids: [tag1.id, tag2.id]})

      Links.subscribe_links(scope)
      refetched = Links.get_link!(scope, link.id)
      target = Enum.find(refetched.link_tags, &(&1.tag_id == tag1.id))

      assert {:ok, :tag_removed} = Links.cleanup_link(target.id)
      assert_receive {:link_updated, broadcast_link}
      assert broadcast_link.id == link.id
      assert length(broadcast_link.link_tags) == 1
    end

    test "does not broadcast when tags remain" do
      scope = user_scope_fixture()
      tag1 = tag_fixture(scope)
      tag2 = tag_fixture(scope)
      link = link_fixture(scope, %{tag_ids: [tag1.id, tag2.id]})

      Links.subscribe_links(scope)
      refetched = Links.get_link!(scope, link.id)
      target = Enum.find(refetched.link_tags, &(&1.tag_id == tag1.id))

      assert {:ok, :tag_removed} = Links.cleanup_link(target.id)
      refute_receive {:link_deleted, _}
    end
  end

  describe "cleanup_expired/0" do
    test "removes expired link_tags and orphaned links" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope, %{expires_in_days: 1})
      link = link_fixture(scope, %{tag_ids: [tag.id]})

      refetched = Links.get_link!(scope, link.id)
      [lt] = refetched.link_tags
      past = DateTime.add(DateTime.utc_now(:second), -1, :day)

      Liminal.Repo.update_all(
        Ecto.Query.from(lt_q in Liminal.Links.LinkTag, where: lt_q.id == ^lt.id),
        set: [expires_at: past]
      )

      assert :ok = Links.cleanup_expired()

      assert [] = Links.list_links(scope, filter: :all)
    end

    test "preserves active (non-expired) link_tags" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope, %{expires_in_days: 30})
      link = link_fixture(scope, %{tag_ids: [tag.id]})

      assert :ok = Links.cleanup_expired()

      refetched = Links.get_link!(scope, link.id)
      assert length(refetched.link_tags) == 1
    end

    test "broadcasts for each orphaned link during sweep" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope, %{expires_in_days: 1})
      link = link_fixture(scope, %{tag_ids: [tag.id]})

      Links.subscribe_links(scope)

      refetched = Links.get_link!(scope, link.id)
      [lt] = refetched.link_tags
      past = DateTime.add(DateTime.utc_now(:second), -1, :day)

      Liminal.Repo.update_all(
        Ecto.Query.from(lt_q in Liminal.Links.LinkTag, where: lt_q.id == ^lt.id),
        set: [expires_at: past]
      )

      assert :ok = Links.cleanup_expired()
      assert_receive {:link_deleted, link_id}
      assert link_id == link.id
    end

    test "only removes expired, keeps remaining tags on same link" do
      scope = user_scope_fixture()
      tag_expiring = tag_fixture(scope, %{expires_in_days: 1})
      tag_lasting = tag_fixture(scope, %{expires_in_days: 365})

      link = link_fixture(scope, %{tag_ids: [tag_expiring.id, tag_lasting.id]})

      refetched = Links.get_link!(scope, link.id)

      expiring_lt =
        Enum.find(refetched.link_tags, &(&1.tag_id == tag_expiring.id))

      past = DateTime.add(DateTime.utc_now(:second), -1, :day)

      Liminal.Repo.update_all(
        Ecto.Query.from(lt_q in Liminal.Links.LinkTag,
          where: lt_q.id == ^expiring_lt.id
        ),
        set: [expires_at: past]
      )

      assert :ok = Links.cleanup_expired()

      refetched = Links.get_link!(scope, link.id)
      assert length(refetched.link_tags) == 1
      assert hd(refetched.link_tags).tag_id == tag_lasting.id
    end
  end

  describe "list_links/2 filtering" do
    test "default filter :unviewed excludes viewed links" do
      scope = user_scope_fixture()
      unviewed_link = link_fixture(scope, %{title: "unviewed"})
      viewed_link = link_fixture(scope, %{title: "viewed"})
      {:ok, _} = Links.mark_viewed(scope, viewed_link)

      results = Links.list_links(scope)
      ids = Enum.map(results, & &1.id)
      assert unviewed_link.id in ids
      refute viewed_link.id in ids
    end

    test "filter :viewed returns only viewed links" do
      scope = user_scope_fixture()
      _unviewed_link = link_fixture(scope, %{title: "unviewed"})
      viewed_link = link_fixture(scope, %{title: "viewed"})
      {:ok, _} = Links.mark_viewed(scope, viewed_link)

      results = Links.list_links(scope, filter: :viewed)
      ids = Enum.map(results, & &1.id)
      assert viewed_link.id in ids
      refute length(ids) > 1
    end

    test "filter :all returns everything" do
      scope = user_scope_fixture()
      unviewed_link = link_fixture(scope, %{title: "unviewed"})
      viewed_link = link_fixture(scope, %{title: "viewed"})
      {:ok, _} = Links.mark_viewed(scope, viewed_link)

      results = Links.list_links(scope, filter: :all)
      ids = Enum.map(results, & &1.id)
      assert unviewed_link.id in ids
      assert viewed_link.id in ids
    end
  end

  describe "ownership enforcement" do
    test "update_link/3 on another user's link raises MatchError" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()
      link = link_fixture(scope_a)

      assert_raise MatchError, fn ->
        Links.update_link(scope_b, link, %{title: "hacked"})
      end
    end

    test "delete_link/2 on another user's link raises MatchError" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()
      link = link_fixture(scope_a)

      assert_raise MatchError, fn ->
        Links.delete_link(scope_b, link)
      end
    end
  end
end
