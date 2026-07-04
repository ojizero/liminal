defmodule Liminal.Links.StatsTest do
  use Liminal.DataCase, async: true

  alias Liminal.Accounts.Scope
  alias Liminal.Links
  alias Liminal.Links.Stats

  setup do
    user = Liminal.AccountsFixtures.user_fixture()
    other_user = Liminal.AccountsFixtures.user_fixture()
    scope = Scope.for_user(user)
    other_scope = Scope.for_user(other_user)

    {:ok, scope: scope, other_scope: other_scope}
  end

  describe "user_stats/1" do
    test "returns counts scoped to the user", %{scope: scope, other_scope: other_scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)
      other_tag = Liminal.LinksFixtures.tag_fixture(other_scope)

      {:ok, _} =
        Links.create_link(scope, %{url: "https://example.com/one"}, [tag.id])

      {:ok, _} =
        Links.create_link(other_scope, %{url: "https://other.com/two"}, [other_tag.id])

      stats = Stats.user_stats(scope)

      assert stats.total_links == 1
      assert stats.unviewed_links == 1
      assert stats.viewed_links == 0
      assert stats.index_failed == 0
    end

    test "counts top bookmarked domains for the user", %{scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)

      for i <- 1..3 do
        {:ok, _} =
          Links.create_link(scope, %{url: "https://news.ycombinator.com/#{i}"}, [tag.id])
      end

      {:ok, _} =
        Links.create_link(scope, %{url: "https://github.com/repo"}, [tag.id])

      stats = Stats.user_stats(scope)

      assert [%{host: "news.ycombinator.com", count: 3}, %{host: "github.com", count: 1}] =
               stats.top_domains
    end

    test "counts links expiring soon", %{scope: scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope, %{expires_in_days: 30})
      {:ok, link} = Links.create_link(scope, %{url: "https://example.com"}, [tag.id])

      soon = DateTime.utc_now(:second) |> DateTime.add(12, :hour)

      link = Links.get_link!(scope, link.id)
      link_tag = hd(link.link_tags)

      Repo.update_all(
        from(lt in Liminal.Links.LinkTag, where: lt.id == ^link_tag.id),
        set: [expires_at: soon]
      )

      stats = Stats.user_stats(scope)

      assert stats.expiring_soon == 1
      assert stats.about_to_expire == 1
    end
  end

  describe "instance_stats/0" do
    test "includes instance-wide fields", %{scope: scope, other_scope: other_scope} do
      tag = Liminal.LinksFixtures.tag_fixture(scope)
      other_tag = Liminal.LinksFixtures.tag_fixture(other_scope)

      {:ok, _} = Links.create_link(scope, %{url: "https://a.com"}, [tag.id])
      {:ok, _} = Links.create_link(other_scope, %{url: "https://b.com"}, [other_tag.id])

      stats = Stats.instance_stats()

      assert stats.total_links == 2
      assert stats.total_users >= 2
      assert Map.has_key?(stats, :index_pending)
      assert Map.has_key?(stats, :index_gave_up)
    end
  end
end
