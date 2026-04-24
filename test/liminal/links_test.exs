defmodule Liminal.LinksTest do
  use Liminal.DataCase

  alias Liminal.Links

  import Liminal.AccountsFixtures
  import Liminal.LinksFixtures

  describe "list_categories/1" do
    test "returns categories scoped to the user" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()

      category = category_fixture(scope_a, %{name: "my category"})
      _other = category_fixture(scope_b, %{name: "other category"})

      categories_a = Links.list_categories(scope_a)
      assert Enum.any?(categories_a, fn c -> c.id == category.id end)
      refute Enum.any?(Links.list_categories(scope_b), fn c -> c.id == category.id end)
    end

    test "returns only default categories for a new user" do
      scope = user_scope_fixture()
      categories = Links.list_categories(scope)
      assert length(categories) == 3
    end
  end

  describe "create_category/2" do
    test "creates a category with valid attrs" do
      scope = user_scope_fixture()

      assert {:ok, category} =
               Links.create_category(scope, %{name: "bookmarks", expires_in_days: 7})

      assert category.name == "bookmarks"
      assert category.expires_in_days == 7
      assert category.user_id == scope.user.id
    end

    test "returns error changeset with blank name" do
      scope = user_scope_fixture()

      assert {:error, changeset} = Links.create_category(scope, %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error changeset for duplicate name for the same user" do
      scope = user_scope_fixture()
      category_fixture(scope, %{name: "dupe"})

      assert {:error, changeset} = Links.create_category(scope, %{name: "dupe"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update_category/3" do
    test "updates name and expires_in_days" do
      scope = user_scope_fixture()
      category = category_fixture(scope, %{name: "old name", expires_in_days: 10})

      assert {:ok, updated} =
               Links.update_category(scope, category, %{name: "new name", expires_in_days: 60})

      assert updated.name == "new name"
      assert updated.expires_in_days == 60
    end
  end

  describe "delete_category/2" do
    test "removes the category" do
      scope = user_scope_fixture()
      category = category_fixture(scope)

      before_count = length(Links.list_categories(scope))
      assert {:ok, _deleted} = Links.delete_category(scope, category)
      assert length(Links.list_categories(scope)) == before_count - 1
    end
  end

  describe "list_links/2" do
    test "returns links scoped to the user with preloaded categories" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()

      link = link_fixture(scope_a)
      _other = link_fixture(scope_b)

      assert [fetched] = Links.list_links(scope_a)
      assert fetched.id == link.id
      assert Ecto.assoc_loaded?(fetched.link_categories)
    end
  end

  describe "create_link/3" do
    test "creates a link with valid attrs and categories" do
      scope = user_scope_fixture()
      category = category_fixture(scope, %{expires_in_days: 14})

      assert {:ok, link} =
               Links.create_link(scope, %{url: "https://example.com", title: "Example"}, [
                 category.id
               ])

      assert link.url == "https://example.com"
      assert link.title == "Example"
      assert link.user_id == scope.user.id

      refetched = Links.get_link!(scope, link.id)
      assert length(refetched.link_categories) == 1
      [lc] = refetched.link_categories
      assert lc.category_id == category.id
      assert lc.expires_at != nil
    end

    test "returns error changeset with blank url" do
      scope = user_scope_fixture()
      category = category_fixture(scope)

      assert {:error, changeset} = Links.create_link(scope, %{url: ""}, [category.id])
      assert %{url: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns {:error, :no_categories} with empty category list" do
      scope = user_scope_fixture()

      assert {:error, :no_categories} =
               Links.create_link(scope, %{url: "https://example.com"}, [])
    end

    test "returns {:error, :no_categories} without category_ids (2-arity)" do
      scope = user_scope_fixture()

      assert {:error, :no_categories} =
               Links.create_link(scope, %{url: "https://example.com"})
    end

    test "returns {:error, :invalid_categories} when category IDs don't all resolve" do
      scope = user_scope_fixture()
      valid_category = category_fixture(scope)
      bogus_id = Ecto.UUID.generate()

      assert {:error, :invalid_categories} =
               Links.create_link(scope, %{url: "https://example.com"}, [
                 valid_category.id,
                 bogus_id
               ])

      # No link should have been created
      assert [] = Links.list_links(scope, filter: :all)
    end

    test "returns {:error, :invalid_categories} when using another user's category" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()
      other_category = category_fixture(scope_b)

      assert {:error, :invalid_categories} =
               Links.create_link(scope_a, %{url: "https://example.com"}, [other_category.id])
    end

    test "creates link_categories with correct expires_at" do
      scope = user_scope_fixture()
      category = category_fixture(scope, %{expires_in_days: 7})

      {:ok, link} =
        Links.create_link(scope, %{url: "https://example.com"}, [category.id])

      refetched = Links.get_link!(scope, link.id)
      [lc] = refetched.link_categories

      expected_approx = DateTime.add(DateTime.utc_now(:second), 7, :day)
      diff = DateTime.diff(lc.expires_at, expected_approx, :second) |> abs()
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
  end

  describe "delete_link/2" do
    test "removes the link" do
      scope = user_scope_fixture()
      link = link_fixture(scope)

      assert {:ok, _deleted} = Links.delete_link(scope, link)
      assert [] = Links.list_links(scope, filter: :all)
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
  end

  describe "tag_link/3" do
    test "creates association and sets expires_at based on category.expires_in_days" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      category = category_fixture(scope, %{expires_in_days: 14})

      assert {:ok, _link_category} = Links.tag_link(scope, link, category)

      refetched = Links.get_link!(scope, link.id)

      assert Enum.any?(refetched.link_categories, fn lc ->
               lc.category.id == category.id and lc.expires_at != nil
             end)
    end

    test "is idempotent — tagging twice does not error" do
      scope = user_scope_fixture()
      link = link_fixture(scope)
      category = category_fixture(scope)

      assert {:ok, _} = Links.tag_link(scope, link, category)
      assert {:ok, _} = Links.tag_link(scope, link, category)
    end
  end

  describe "untag_link/1" do
    test "removes the link_category by ID" do
      scope = user_scope_fixture()
      cat1 = category_fixture(scope)
      cat2 = category_fixture(scope)
      link = link_fixture(scope, %{category_ids: [cat1.id, cat2.id]})

      refetched = Links.get_link!(scope, link.id)
      target = Enum.find(refetched.link_categories, &(&1.category_id == cat1.id))

      assert :ok = Links.untag_link(target.id)

      refetched = Links.get_link!(scope, link.id)
      assert length(refetched.link_categories) == 1
    end

    test "is idempotent — calling twice does not error" do
      scope = user_scope_fixture()
      category = category_fixture(scope)
      link = link_fixture(scope, %{category_ids: [category.id]})

      refetched = Links.get_link!(scope, link.id)
      [lc] = refetched.link_categories

      assert :ok = Links.untag_link(lc.id)
      assert :ok = Links.untag_link(lc.id)
    end
  end

  describe "cleanup_link/3" do
    test "removes the association and returns {:ok, :category_removed}" do
      scope = user_scope_fixture()
      cat1 = category_fixture(scope)
      cat2 = category_fixture(scope)
      link = link_fixture(scope, %{category_ids: [cat1.id, cat2.id]})

      assert {:ok, :category_removed} = Links.cleanup_link(scope, link, cat1)

      refetched = Links.get_link!(scope, link.id)
      assert length(refetched.link_categories) == 1
    end

    test "deletes the link when removing last category and returns {:ok, :link_deleted}" do
      scope = user_scope_fixture()
      category = category_fixture(scope)
      link = link_fixture(scope, %{category_ids: [category.id]})

      assert {:ok, :link_deleted} = Links.cleanup_link(scope, link, category)

      assert [] = Links.list_links(scope, filter: :all)
    end

    test "is idempotent — returns {:ok, :category_removed} if already untagged" do
      scope = user_scope_fixture()
      cat1 = category_fixture(scope)
      cat2 = category_fixture(scope)
      link = link_fixture(scope, %{category_ids: [cat1.id, cat2.id]})

      assert {:ok, :category_removed} = Links.cleanup_link(scope, link, cat1)
      assert {:ok, :category_removed} = Links.cleanup_link(scope, link, cat1)
    end
  end

  describe "cleanup_link/1" do
    test "removes the targeted link_category and checks orphan" do
      scope = user_scope_fixture()
      cat1 = category_fixture(scope)
      cat2 = category_fixture(scope)
      link = link_fixture(scope, %{category_ids: [cat1.id, cat2.id]})

      refetched = Links.get_link!(scope, link.id)
      target = Enum.find(refetched.link_categories, &(&1.category_id == cat1.id))

      assert {:ok, :category_removed} = Links.cleanup_link(target.id)

      refetched = Links.get_link!(scope, link.id)
      assert length(refetched.link_categories) == 1
    end

    test "deletes the link when it becomes orphaned" do
      scope = user_scope_fixture()
      category = category_fixture(scope)
      link = link_fixture(scope, %{category_ids: [category.id]})

      refetched = Links.get_link!(scope, link.id)
      [lc] = refetched.link_categories

      assert {:ok, :link_deleted} = Links.cleanup_link(lc.id)

      assert [] = Links.list_links(scope, filter: :all)
    end

    test "returns {:ok, :category_removed} for a non-existent ID" do
      assert {:ok, :category_removed} = Links.cleanup_link(Ecto.UUID.generate())
    end
  end

  describe "cleanup_expired/0" do
    test "removes expired link_categories and orphaned links" do
      scope = user_scope_fixture()
      category = category_fixture(scope, %{expires_in_days: 1})
      link = link_fixture(scope, %{category_ids: [category.id]})

      refetched = Links.get_link!(scope, link.id)
      [lc] = refetched.link_categories
      past = DateTime.add(DateTime.utc_now(:second), -1, :day)

      Liminal.Repo.update_all(
        Ecto.Query.from(lc_q in Liminal.Links.LinkCategory, where: lc_q.id == ^lc.id),
        set: [expires_at: past]
      )

      assert :ok = Links.cleanup_expired()

      assert [] = Links.list_links(scope, filter: :all)
    end

    test "preserves active (non-expired) link_categories" do
      scope = user_scope_fixture()
      category = category_fixture(scope, %{expires_in_days: 30})
      link = link_fixture(scope, %{category_ids: [category.id]})

      assert :ok = Links.cleanup_expired()

      refetched = Links.get_link!(scope, link.id)
      assert length(refetched.link_categories) == 1
    end

    test "only removes expired, keeps remaining categories on same link" do
      scope = user_scope_fixture()
      cat_expiring = category_fixture(scope, %{expires_in_days: 1})
      cat_lasting = category_fixture(scope, %{expires_in_days: 365})

      link = link_fixture(scope, %{category_ids: [cat_expiring.id, cat_lasting.id]})

      refetched = Links.get_link!(scope, link.id)

      expiring_lc =
        Enum.find(refetched.link_categories, &(&1.category_id == cat_expiring.id))

      past = DateTime.add(DateTime.utc_now(:second), -1, :day)

      Liminal.Repo.update_all(
        Ecto.Query.from(lc_q in Liminal.Links.LinkCategory,
          where: lc_q.id == ^expiring_lc.id
        ),
        set: [expires_at: past]
      )

      assert :ok = Links.cleanup_expired()

      refetched = Links.get_link!(scope, link.id)
      assert length(refetched.link_categories) == 1
      assert hd(refetched.link_categories).category_id == cat_lasting.id
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
