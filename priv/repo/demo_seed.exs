# Populates the dev database with demo data for stats and reindex screenshots.
# Run: mix run priv/repo/demo_seed.exs

import Ecto.Query

alias Liminal.{Accounts, Links, Repo}
alias Liminal.Accounts.Scope
alias Liminal.Links.{Link, LinkTag}

admin =
  case Accounts.get_user_by_username("admin") do
    nil ->
      {:ok, user} =
        Accounts.register_user(%{
          username: "admin",
          password: "password123!",
          password_confirmation: "password123!"
        })

      Repo.update!(Ecto.Changeset.change(user, role: "admin"))

    user ->
      Repo.update!(Ecto.Changeset.change(user, role: "admin"))
  end

demo =
  case Accounts.get_user_by_username("demo") do
    nil ->
      {:ok, user} =
        Accounts.register_user(%{
          username: "demo",
          password: "password123!",
          password_confirmation: "password123!"
        })

      user

    user ->
      user
  end

admin_scope = Scope.for_user(admin)
demo_scope = Scope.for_user(demo)

# Clear existing links for a clean demo
from(l in Link) |> Repo.delete_all()

now = DateTime.utc_now(:second)

seed_links = fn scope, entries ->
  tag = Links.list_tags(scope) |> List.first()

  Enum.each(entries, fn {url, attrs} ->
    {:ok, link} = Links.create_link(scope, Map.put(attrs, :url, url), [tag.id])

    if attrs[:viewed] do
      Links.mark_viewed(scope, link)
    end

    if attrs[:indexed] do
      Repo.update_all(from(l in Link, where: l.id == ^link.id),
        set: [
          indexed_at: now,
          title: attrs[:title] || "Indexed title",
          description: "Demo description"
        ]
      )
    end

    if attrs[:failed] do
      Repo.update_all(from(l in Link, where: l.id == ^link.id),
        set: [index_attempt_count: 3, index_last_attempted_at: now]
      )
    end

    if attrs[:gave_up] do
      Repo.update_all(from(l in Link, where: l.id == ^link.id),
        set: [index_attempt_count: 10, index_gave_up_at: now, index_last_attempted_at: now]
      )
    end

    if expiry = attrs[:expires_at] do
      link = Links.get_link!(scope, link.id)
      link_tag = hd(link.link_tags)

      Repo.update_all(from(lt in LinkTag, where: lt.id == ^link_tag.id),
        set: [expires_at: expiry]
      )
    end
  end)
end

soon = DateTime.add(now, 12, :hour)
week = DateTime.add(now, 3, :day)

demo_entries = [
  {"https://news.ycombinator.com/item/1", %{title: "HN Story 1"}},
  {"https://news.ycombinator.com/item/2", %{title: "HN Story 2"}},
  {"https://news.ycombinator.com/item/3", %{title: "HN Story 3"}},
  {"https://github.com/ojizero/liminal", %{title: "Liminal repo", indexed: true}},
  {"https://github.com/elixir-lang/elixir", %{title: "Elixir", indexed: true, viewed: true}},
  {"https://phoenixframework.org/", %{title: "Phoenix", indexed: true}},
  {"https://expiring-soon.example.com/", %{title: "Expires soon", expires_at: soon}},
  {"https://expiring-week.example.com/", %{title: "Expires this week", expires_at: week}},
  {"https://failed-index.example.com/broken", %{title: nil, failed: true}},
  {"https://gave-up.example.com/dead", %{title: nil, gave_up: true}}
]

admin_entries = [
  {"https://news.ycombinator.com/admin", %{title: "Admin HN"}},
  {"https://github.com/ojizero/liminal", %{title: "Admin repo dup"}},
  {"https://other.example.com/page", %{title: "Other site", viewed: true, indexed: true}}
]

seed_links.(demo_scope, demo_entries)
seed_links.(admin_scope, admin_entries)

IO.puts("Demo seed complete.")
IO.puts("  admin / password123!")
IO.puts("  demo  / password123!")
IO.puts("  Links: #{Repo.aggregate(Link, :count)}")
