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

    test "prepends https:// when url lacks a scheme" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope)

      assert {:ok, link} =
               Links.create_link(scope, %{url: "example.com/no-scheme"}, [tag.id])

      assert link.url == "https://example.com/no-scheme"
    end

    test "preserves an existing http:// scheme" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope)

      assert {:ok, link} =
               Links.create_link(scope, %{url: "http://example.com/insecure"}, [tag.id])

      assert link.url == "http://example.com/insecure"
    end

    test "returns error changeset for invalid url" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope)

      assert {:error, changeset} = Links.create_link(scope, %{url: "not-a-url"}, [tag.id])
      assert %{url: ["must be a valid URL"]} = errors_on(changeset)
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

    test "saves an optional note" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope)

      assert {:ok, link} =
               Links.create_link(
                 scope,
                 %{url: "https://example.com", note: "Read this later"},
                 [tag.id]
               )

      assert link.note == "Read this later"
    end

    test "returns error changeset when note exceeds 500 characters" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope)

      assert {:error, changeset} =
               Links.create_link(
                 scope,
                 %{url: "https://example.com", note: String.duplicate("a", 501)},
                 [tag.id]
               )

      assert %{note: ["should be at most 500 character(s)"]} = errors_on(changeset)
    end
  end

  describe "find_link_by_url/2" do
    test "returns the link when URL matches for the user" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{url: "https://example.org"})

      assert %{} = found = Links.find_link_by_url(scope, "https://example.org")
      assert found.id == link.id
      assert Ecto.assoc_loaded?(found.link_tags)
    end

    test "returns nil when URL does not exist" do
      scope = user_scope_fixture()

      assert Links.find_link_by_url(scope, "https://missing.example") == nil
    end

    test "returns nil for another user's link with the same URL" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()
      _link = link_fixture(scope_a, %{url: "https://example.org"})

      assert Links.find_link_by_url(scope_b, "https://example.org") == nil
    end
  end

  describe "merge_link_tags/3" do
    test "adds new tags, refreshes expiry on selected existing tags, and keeps others" do
      scope = user_scope_fixture()
      foo = tag_fixture(scope, %{name: "foo", expires_in_days: 30})
      bar = tag_fixture(scope, %{name: "bar", expires_in_days: 30})
      baz = tag_fixture(scope, %{name: "baz", expires_in_days: 14})

      link =
        link_fixture(scope, %{
          url: "https://example.org",
          tag_ids: [foo.id, bar.id]
        })

      refetched = Links.get_link!(scope, link.id)
      foo_lt = Enum.find(refetched.link_tags, &(&1.tag_id == foo.id))
      bar_lt = Enum.find(refetched.link_tags, &(&1.tag_id == bar.id))

      stale_expires_at = DateTime.add(DateTime.utc_now(:second), -1, :day)

      from(lt in Liminal.Links.LinkTag, where: lt.id == ^foo_lt.id)
      |> Liminal.Repo.update_all(set: [expires_at: stale_expires_at])

      assert {:ok, updated} = Links.merge_link_tags(scope, refetched, [foo.id, baz.id])

      tag_ids = Enum.map(updated.link_tags, & &1.tag_id)
      assert foo.id in tag_ids
      assert bar.id in tag_ids
      assert baz.id in tag_ids
      assert length(updated.link_tags) == 3

      refreshed_foo = Enum.find(updated.link_tags, &(&1.tag_id == foo.id))
      unchanged_bar = Enum.find(updated.link_tags, &(&1.tag_id == bar.id))
      added_baz = Enum.find(updated.link_tags, &(&1.tag_id == baz.id))

      assert DateTime.compare(refreshed_foo.expires_at, stale_expires_at) == :gt
      assert unchanged_bar.expires_at == bar_lt.expires_at
      assert added_baz.expires_at != nil
    end

    test "returns {:error, :invalid_tags} for invalid tag IDs" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{url: "https://example.org"})

      assert {:error, :invalid_tags} =
               Links.merge_link_tags(scope, link, [Ecto.UUID.generate()])
    end

    test "returns {:error, :no_tags} with empty tag list" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{url: "https://example.org"})

      assert {:error, :no_tags} = Links.merge_link_tags(scope, link, [])
    end

    test "broadcasts {:link_updated, link} on success" do
      scope = user_scope_fixture()
      foo = tag_fixture(scope, %{name: "foo"})
      bar = tag_fixture(scope, %{name: "bar"})
      link = link_fixture(scope, %{url: "https://example.org", tag_ids: [foo.id]})

      Links.subscribe_links(scope)
      refetched = Links.get_link!(scope, link.id)
      assert {:ok, _} = Links.merge_link_tags(scope, refetched, [foo.id, bar.id])

      assert_receive {:link_updated, broadcast_link}
      assert Enum.count(broadcast_link.link_tags) == 2
    end
  end

  describe "update_link/3" do
    test "updates the title" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: "Old Title"})

      assert {:ok, updated} = Links.update_link(scope, link, %{title: "New Title"})
      assert updated.title == "New Title"
    end

    test "updates the note" do
      scope = user_scope_fixture()
      link = link_fixture(scope)

      assert {:ok, updated} = Links.update_link(scope, link, %{"note" => "A handy note"})
      assert updated.note == "A handy note"
    end

    test "returns error changeset when note exceeds 500 characters" do
      scope = user_scope_fixture()
      link = link_fixture(scope)

      assert {:error, changeset} =
               Links.update_link(scope, link, %{"note" => String.duplicate("a", 501)})

      assert %{note: ["should be at most 500 character(s)"]} = errors_on(changeset)
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

  describe "link_expires_at/1" do
    test "returns latest tag expires_at for unviewed links" do
      scope = user_scope_fixture()
      tag_soon = tag_fixture(scope, %{expires_in_days: 7})
      tag_later = tag_fixture(scope, %{expires_in_days: 30})
      link = link_fixture(scope, %{tag_ids: [tag_soon.id, tag_later.id]})
      link = Links.get_link!(scope, link.id)

      expected =
        link.link_tags
        |> Enum.map(& &1.expires_at)
        |> Enum.max(DateTime)

      assert Links.link_expires_at(link) == expected
    end

    test "returns viewed_at plus grace period for viewed links" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope, %{expires_in_days: 365})
      link = link_fixture(scope, %{tag_ids: [tag.id]})
      {:ok, viewed_link} = Links.mark_viewed(scope, link)

      grace_seconds = Application.get_env(:liminal, :viewed_grace_seconds, 86_400)
      expected = DateTime.add(viewed_link.viewed_at, grace_seconds, :second)

      assert Links.link_expires_at(viewed_link) == expected
    end

    test "viewed expiry ignores tag expires_at even when tags expire later" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope, %{expires_in_days: 365})
      link = link_fixture(scope, %{tag_ids: [tag.id]})
      {:ok, viewed_link} = Links.mark_viewed(scope, link)

      [lt] = viewed_link.link_tags
      assert DateTime.compare(Links.link_expires_at(viewed_link), lt.expires_at) == :lt
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

    test "removes viewed links after grace period even when tags are not expired" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope, %{expires_in_days: 365})
      link = link_fixture(scope, %{tag_ids: [tag.id]})
      {:ok, _} = Links.mark_viewed(scope, link)

      past = DateTime.add(DateTime.utc_now(:second), -2, :day)

      Liminal.Repo.update_all(
        from(l in Liminal.Links.Link, where: l.id == ^link.id),
        set: [viewed_at: past]
      )

      assert :ok = Links.cleanup_expired()

      assert_raise Ecto.NoResultsError, fn ->
        Links.get_link!(scope, link.id)
      end
    end

    test "preserves recently viewed links before grace period elapses" do
      scope = user_scope_fixture()
      tag = tag_fixture(scope, %{expires_in_days: 365})
      link = link_fixture(scope, %{tag_ids: [tag.id]})
      {:ok, _} = Links.mark_viewed(scope, link)

      assert :ok = Links.cleanup_expired()

      refetched = Links.get_link!(scope, link.id)
      assert refetched.viewed_at != nil
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

  describe "list_links/2 tag filtering and sorting" do
    test "tag_ids filter returns only links with matching tags" do
      scope = user_scope_fixture()
      tag1 = tag_fixture(scope)
      tag2 = tag_fixture(scope)
      link1 = link_fixture(scope, %{tag_ids: [tag1.id]})
      _link2 = link_fixture(scope, %{tag_ids: [tag2.id]})

      results = Links.list_links(scope, filter: :all, tag_ids: [tag1.id])
      ids = Enum.map(results, & &1.id)
      assert link1.id in ids
      assert length(ids) == 1
    end

    test "empty tag_ids returns all links" do
      scope = user_scope_fixture()
      tag1 = tag_fixture(scope)
      tag2 = tag_fixture(scope)
      link1 = link_fixture(scope, %{tag_ids: [tag1.id]})
      link2 = link_fixture(scope, %{tag_ids: [tag2.id]})

      results = Links.list_links(scope, filter: :all, tag_ids: [])
      ids = Enum.map(results, & &1.id)
      assert link1.id in ids
      assert link2.id in ids
    end

    test "tag_ids with multiple IDs returns union (any match)" do
      scope = user_scope_fixture()
      tag1 = tag_fixture(scope)
      tag2 = tag_fixture(scope)
      tag3 = tag_fixture(scope)
      link1 = link_fixture(scope, %{tag_ids: [tag1.id]})
      link2 = link_fixture(scope, %{tag_ids: [tag2.id]})
      _link3 = link_fixture(scope, %{tag_ids: [tag3.id]})

      results = Links.list_links(scope, filter: :all, tag_ids: [tag1.id, tag2.id])
      ids = Enum.map(results, & &1.id)
      assert link1.id in ids
      assert link2.id in ids
      assert length(ids) == 2
    end

    test "sort :time_added_asc returns oldest first" do
      scope = user_scope_fixture()
      link1 = link_fixture(scope, %{title: "older"})
      link2 = link_fixture(scope, %{title: "newer"})

      past = DateTime.utc_now(:second) |> DateTime.add(-1, :hour)

      Liminal.Repo.update_all(
        Ecto.Query.from(l in Liminal.Links.Link, where: l.id == ^link1.id),
        set: [inserted_at: past]
      )

      results = Links.list_links(scope, filter: :all, sort: :time_added_asc)
      ids = Enum.map(results, & &1.id)
      assert [link1.id, link2.id] == ids
    end

    test "sort :expiring_soon orders by max expires_at ascending" do
      scope = user_scope_fixture()
      tag_soon = tag_fixture(scope, %{expires_in_days: 7})
      tag_later = tag_fixture(scope, %{expires_in_days: 30})
      link1 = link_fixture(scope, %{tag_ids: [tag_soon.id]})
      link2 = link_fixture(scope, %{tag_ids: [tag_later.id]})

      results = Links.list_links(scope, filter: :all, sort: :expiring_soon)
      ids = Enum.map(results, & &1.id)
      assert [link1.id, link2.id] == ids
    end

    test "sort :expiring_soon puts nil expiry last" do
      scope = user_scope_fixture()
      tag_with_expiry = tag_fixture(scope, %{expires_in_days: 7})
      tag_no_expiry = tag_fixture(scope, %{expires_in_days: nil})
      link1 = link_fixture(scope, %{tag_ids: [tag_with_expiry.id]})
      link2 = link_fixture(scope, %{tag_ids: [tag_no_expiry.id]})

      results = Links.list_links(scope, filter: :all, sort: :expiring_soon)
      ids = Enum.map(results, & &1.id)
      assert [link1.id, link2.id] == ids
    end

    test "combined filter, tag_ids, and sort" do
      scope = user_scope_fixture()
      tag1 = tag_fixture(scope)
      tag2 = tag_fixture(scope)
      link1 = link_fixture(scope, %{title: "unviewed-tag1", tag_ids: [tag1.id]})
      link2 = link_fixture(scope, %{title: "viewed-tag1", tag_ids: [tag1.id]})
      _link3 = link_fixture(scope, %{title: "unviewed-tag2", tag_ids: [tag2.id]})

      {:ok, _} = Links.mark_viewed(scope, link2)

      results =
        Links.list_links(scope,
          filter: :unviewed,
          tag_ids: [tag1.id],
          sort: :time_added_desc
        )

      ids = Enum.map(results, & &1.id)
      assert ids == [link1.id]
    end
  end

  describe "list_links/2 search" do
    test "query matches title" do
      scope = user_scope_fixture()
      matching = link_fixture(scope, %{title: "Phoenix LiveView Patterns"})
      _other = link_fixture(scope, %{title: "Unrelated bookmark"})

      results = Links.list_links(scope, filter: :all, query: "liveview")
      ids = Enum.map(results, & &1.id)
      assert matching.id in ids
      assert length(ids) == 1
    end

    test "query matches note and description" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: "Docs", note: "Check deployment steps"})
      {:ok, _link} = Links.update_link_metadata(link, %{description: "Official deployment guide"})

      assert [_] = Links.list_links(scope, filter: :all, query: "deploymnt")
      assert [_] = Links.list_links(scope, filter: :all, query: "deplyment steps")
    end

    test "query matches url with typos" do
      scope = user_scope_fixture()

      matching =
        link_fixture(scope, %{
          url: "https://github.com/elixir-lang/elixir",
          title: "Repo"
        })

      _other = link_fixture(scope, %{url: "https://example.com/other", title: "Other"})

      results = Links.list_links(scope, filter: :all, query: "githib elxir")
      assert Enum.map(results, & &1.id) == [matching.id]
    end

    test "empty query returns all links" do
      scope = user_scope_fixture()
      link1 = link_fixture(scope, %{title: "One"})
      link2 = link_fixture(scope, %{title: "Two"})

      results = Links.list_links(scope, filter: :all, query: "")
      ids = Enum.map(results, & &1.id)
      assert link1.id in ids
      assert link2.id in ids
    end

    test "search composes with filter and tag_ids" do
      scope = user_scope_fixture()
      tag1 = tag_fixture(scope)
      tag2 = tag_fixture(scope)

      matching =
        link_fixture(scope, %{
          title: "Searchable tagged link",
          tag_ids: [tag1.id]
        })

      _wrong_tag =
        link_fixture(scope, %{
          title: "Searchable other tag",
          tag_ids: [tag2.id]
        })

      _wrong_title = link_fixture(scope, %{title: "Different", tag_ids: [tag1.id]})

      results =
        Links.list_links(scope,
          filter: :all,
          tag_ids: [tag1.id],
          query: "serchable tagged"
        )

      assert Enum.map(results, & &1.id) == [matching.id]
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

  describe "update_link_metadata/2" do
    test "updates metadata fields on a link without a title" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})

      metadata = %{
        title: "Fetched Title",
        description: "A description from the page",
        favicon_url: "https://example.com/favicon.ico"
      }

      assert {:ok, updated} = Links.update_link_metadata(link, metadata)
      assert updated.title == "Fetched Title"
      assert updated.description == "A description from the page"
      assert updated.favicon_url == "https://example.com/favicon.ico"
      assert updated.indexed_at != nil
    end

    test "preserves user-provided title" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: "My Custom Title"})

      metadata = %{
        title: "Fetched Title That Should Be Ignored",
        description: "Some description"
      }

      assert {:ok, updated} = Links.update_link_metadata(link, metadata)
      assert updated.title == "My Custom Title"
      assert updated.description == "Some description"
      assert updated.indexed_at != nil
    end

    test "broadcasts {:link_updated, link} on success" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})

      Links.subscribe_links(scope)

      metadata = %{title: "Broadcast Title", description: "desc"}
      {:ok, _updated} = Links.update_link_metadata(link, metadata)

      assert_receive {:link_updated, broadcast_link}
      assert broadcast_link.id == link.id
      assert broadcast_link.title == "Broadcast Title"
      assert broadcast_link.indexed_at != nil
      assert Ecto.assoc_loaded?(broadcast_link.link_tags)
    end
  end

  describe "list_index_retry_candidates/1" do
    test "returns links without indexed_at that are old enough" do
      scope = user_scope_fixture()
      link = link_fixture(scope)

      past = DateTime.utc_now(:second) |> DateTime.add(-2, :minute)

      Liminal.Repo.update_all(
        Ecto.Query.from(l in Liminal.Links.Link, where: l.id == ^link.id),
        set: [inserted_at: past]
      )

      results = Links.list_index_retry_candidates()
      assert Enum.any?(results, fn l -> l.id == link.id end)
    end

    test "excludes recently created links" do
      scope = user_scope_fixture()
      link = link_fixture(scope)

      results = Links.list_index_retry_candidates()
      refute Enum.any?(results, fn l -> l.id == link.id end)
    end

    test "excludes already indexed links" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})

      past = DateTime.utc_now(:second) |> DateTime.add(-2, :minute)

      Liminal.Repo.update_all(
        Ecto.Query.from(l in Liminal.Links.Link, where: l.id == ^link.id),
        set: [inserted_at: past]
      )

      {:ok, _} = Links.update_link_metadata(link, %{title: "Indexed"})

      results = Links.list_index_retry_candidates()
      refute Enum.any?(results, fn l -> l.id == link.id end)
    end

    test "excludes links with future next attempt" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      past = DateTime.utc_now(:second) |> DateTime.add(-2, :minute)
      future = DateTime.utc_now(:second) |> DateTime.add(1, :hour)

      Liminal.Repo.update_all(
        Ecto.Query.from(l in Liminal.Links.Link, where: l.id == ^link.id),
        set: [inserted_at: past, index_next_attempt_at: future]
      )

      results = Links.list_index_retry_candidates()
      refute Enum.any?(results, fn l -> l.id == link.id end)
    end

    test "excludes links that gave up" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      past = DateTime.utc_now(:second) |> DateTime.add(-2, :minute)
      now = DateTime.utc_now(:second)

      Liminal.Repo.update_all(
        Ecto.Query.from(l in Liminal.Links.Link, where: l.id == ^link.id),
        set: [inserted_at: past, index_gave_up_at: now]
      )

      results = Links.list_index_retry_candidates()
      refute Enum.any?(results, fn l -> l.id == link.id end)
    end

    test "includes failed links before inserted_at cutoff when already attempted" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      future = DateTime.utc_now(:second) |> DateTime.add(1, :hour)

      Liminal.Repo.update_all(
        Ecto.Query.from(l in Liminal.Links.Link, where: l.id == ^link.id),
        set: [
          index_attempt_count: 1,
          index_last_attempted_at: DateTime.utc_now(:second),
          index_next_attempt_at: future
        ]
      )

      results = Links.list_index_retry_candidates()
      refute Enum.any?(results, fn l -> l.id == link.id end)

      past = DateTime.utc_now(:second) |> DateTime.add(-5, :second)

      Liminal.Repo.update_all(
        Ecto.Query.from(l in Liminal.Links.Link, where: l.id == ^link.id),
        set: [index_next_attempt_at: past]
      )

      results = Links.list_index_retry_candidates()
      assert Enum.any?(results, fn l -> l.id == link.id end)
    end

    test "respects limit option" do
      scope = user_scope_fixture()
      past = DateTime.utc_now(:second) |> DateTime.add(-2, :minute)

      for _ <- 1..3 do
        l = link_fixture(scope)

        Liminal.Repo.update_all(
          Ecto.Query.from(lnk in Liminal.Links.Link, where: lnk.id == ^l.id),
          set: [inserted_at: past]
        )
      end

      results = Links.list_index_retry_candidates(limit: 2)
      assert length(results) == 2
    end
  end

  describe "record_index_failure/1" do
    test "increments attempt count and schedules next retry" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})

      assert {:ok, updated} = Links.record_index_failure(link)
      assert updated.index_attempt_count == 1
      assert updated.index_last_attempted_at != nil
      assert updated.index_next_attempt_at != nil
      assert is_nil(updated.index_gave_up_at)
    end

    test "gives up after max attempts" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})

      Application.put_env(:liminal, Liminal.Retry, max_attempts: 3)

      on_exit(fn -> Application.delete_env(:liminal, Liminal.Retry) end)

      {:ok, link} = Links.record_index_failure(link)
      {:ok, link} = Links.record_index_failure(link)
      assert {:ok, updated} = Links.record_index_failure(link)

      assert updated.index_attempt_count == 3
      assert updated.index_gave_up_at != nil
      assert is_nil(updated.index_next_attempt_at)
    end
  end

  describe "retry_indexing/2" do
    test "resets retry state for gave-up link" do
      scope = user_scope_fixture()
      link = link_fixture(scope, %{title: nil})
      now = DateTime.utc_now(:second)

      Liminal.Repo.update_all(
        Ecto.Query.from(l in Liminal.Links.Link, where: l.id == ^link.id),
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
  end

  describe "list_unindexed_links/1" do
    test "delegates to list_index_retry_candidates/1" do
      scope = user_scope_fixture()
      link = link_fixture(scope)

      past = DateTime.utc_now(:second) |> DateTime.add(-2, :minute)

      Liminal.Repo.update_all(
        Ecto.Query.from(l in Liminal.Links.Link, where: l.id == ^link.id),
        set: [inserted_at: past]
      )

      assert Links.list_unindexed_links() == Links.list_index_retry_candidates()
    end
  end
end
