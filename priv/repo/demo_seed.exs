# Demo / local-development seed data for Liminal.
#
# Loaded automatically by `mix ecto.setup` / `mix setup` in `:dev` (via seeds.exs).
# Re-run anytime (rebuilds seeded users' links/tags):
#
#     mix run priv/repo/demo_seed.exs
#
# Shared password for all password-bearing seeded accounts: liminaldev123!
#
# See AGENTS.md → "Dev seed data" for the inventory of accounts and scenarios.

import Ecto.Query

alias Liminal.{Accounts, Links, Repo}
alias Liminal.Accounts.{Scope, User}
alias Liminal.Links.{Link, LinkTag}

password = "liminaldev123!"
user_attrs = %{password: password, password_confirmation: password}
default_tag_names = ["saved for later", "read later", "watch later"]

# Avoid outbound metadata fetches while seeding.
previous_indexer = Application.get_env(:liminal, :start_indexer, true)
Application.put_env(:liminal, :start_indexer, false)

try do
  ensure_user = fn username, opts ->
    role = Keyword.get(opts, :role, "user")
    disabled? = Keyword.get(opts, :disabled, false)

    user =
      case Accounts.get_user_by_username(username) do
        nil ->
          {:ok, user} = Accounts.register_user(Map.put(user_attrs, :username, username))
          user

        existing ->
          existing
      end

    user
    |> Ecto.Changeset.change(role: role)
    |> then(fn cs ->
      if disabled? do
        Ecto.Changeset.put_change(cs, :disabled_at, DateTime.utc_now(:second))
      else
        Ecto.Changeset.put_change(cs, :disabled_at, nil)
      end
    end)
    |> Repo.update!()
  end

  ensure_tag = fn scope, name, expires_in_days ->
    case Enum.find(Links.list_tags(scope), &(&1.name == name)) do
      nil ->
        {:ok, tag} = Links.create_tag(scope, %{name: name, expires_in_days: expires_in_days})
        tag

      tag ->
        {:ok, tag} = Links.update_tag(scope, tag, %{expires_in_days: expires_in_days})
        tag
    end
  end

  tag_by_name = fn scope, name ->
    Enum.find(Links.list_tags(scope), &(&1.name == name)) ||
      raise "missing tag #{inspect(name)} for #{scope.user.username}"
  end

  clear_user_links = fn user_id ->
    link_ids = from(l in Link, where: l.user_id == ^user_id, select: l.id) |> Repo.all()

    if link_ids != [] do
      from(lt in LinkTag, where: lt.link_id in ^link_ids) |> Repo.delete_all()
      from(l in Link, where: l.id in ^link_ids) |> Repo.delete_all()
    end
  end

  # Drop custom tags outside the keep list so re-seeds stay deterministic.
  # Default tags created at registration are always retained.
  clear_custom_tags = fn scope, keep_names ->
    keep = MapSet.new(default_tag_names ++ keep_names)
    user = Accounts.get_user!(scope.user.id)

    for tag <- Links.list_tags(scope), not MapSet.member?(keep, tag.name) do
      if user.default_tag_id == tag.id do
        Repo.update!(
          Ecto.Changeset.change(user, default_tag_id: nil, default_tags_enabled: false)
        )
      end

      {:ok, _} = Links.delete_tag(scope, tag)
    end
  end

  seed_link = fn scope, attrs ->
    tag_ids = Enum.map(attrs.tags, & &1.id)
    now = DateTime.utc_now(:second)

    {:ok, link} =
      Links.create_link(
        scope,
        %{
          url: attrs.url,
          title: attrs[:title],
          note: attrs[:note]
        },
        tag_ids
      )

    link =
      cond do
        attrs[:gave_up] ->
          link
          |> Ecto.Changeset.change(%{
            title: attrs[:title],
            description: attrs[:description],
            favicon_url: attrs[:favicon_url],
            duration_seconds: attrs[:duration_seconds],
            indexed_at: nil,
            index_attempt_count: 10,
            index_gave_up_at: now,
            index_last_attempted_at: now,
            index_next_attempt_at: nil
          })
          |> Repo.update!()

        attrs[:failed] ->
          # Keep below max_attempts (3 in :dev) so this stays "retrying", not gave-up.
          # Schedule next attempt far ahead so the janitor does not immediately re-fetch.
          link
          |> Ecto.Changeset.change(%{
            title: attrs[:title],
            description: attrs[:description],
            favicon_url: attrs[:favicon_url],
            duration_seconds: attrs[:duration_seconds],
            indexed_at: nil,
            index_attempt_count: 2,
            index_last_attempted_at: now,
            index_next_attempt_at: DateTime.add(now, 7, :day),
            index_gave_up_at: nil
          })
          |> Repo.update!()

        attrs[:pending] ->
          # Unindexed, but next attempt deferred so it survives while the server is running.
          link
          |> Ecto.Changeset.change(%{
            title: attrs[:title],
            description: attrs[:description],
            indexed_at: nil,
            index_attempt_count: 0,
            index_last_attempted_at: nil,
            index_next_attempt_at: DateTime.add(now, 7, :day),
            index_gave_up_at: nil
          })
          |> Repo.update!()

        attrs[:indexed] ->
          link
          |> Link.metadata_changeset(%{
            title: attrs[:title],
            description: attrs[:description],
            favicon_url: attrs[:favicon_url],
            duration_seconds: attrs[:duration_seconds],
            indexed_at: now,
            index_attempt_count: 0,
            index_last_attempted_at: nil,
            index_next_attempt_at: nil,
            index_gave_up_at: nil
          })
          |> Repo.update!()

        true ->
          link
      end

    if attrs[:viewed] do
      {:ok, _link} = Links.mark_viewed(scope, link)
    end

    if expires_overrides = attrs[:expires_overrides] do
      link = Links.get_link!(scope, link.id)

      Enum.each(expires_overrides, fn {tag_name, expires_at} ->
        link_tag =
          Enum.find(link.link_tags, fn lt -> lt.tag.name == tag_name end) ||
            raise "no link_tag for #{tag_name} on #{attrs.url}"

        from(lt in LinkTag, where: lt.id == ^link_tag.id)
        |> Repo.update_all(set: [expires_at: expires_at])
      end)
    end

    :ok
  end

  # --- Users -----------------------------------------------------------------

  admin = ensure_user.("admin", role: "admin")
  demo = ensure_user.("demo", role: "user")
  alice = ensure_user.("alice", role: "user")
  _disabled = ensure_user.("disabled", role: "user", disabled: true)

  admin_scope = Scope.for_user(admin)

  _invited =
    case Accounts.get_user_by_username("invited") do
      nil ->
        {:ok, {user, _token}} =
          Accounts.invite_user(admin_scope, %{username: "invited", role: "user"})

        user

      user ->
        user
    end

  demo_scope = Scope.for_user(demo)
  alice_scope = Scope.for_user(alice)

  # --- Tags ------------------------------------------------------------------

  clear_user_links.(demo.id)
  clear_user_links.(alice.id)
  clear_user_links.(admin.id)
  clear_user_links.(_disabled.id)
  clear_user_links.(_invited.id)

  clear_custom_tags.(demo_scope, ["inbox", "side project"])
  clear_custom_tags.(alice_scope, ["reading list"])
  clear_custom_tags.(admin_scope, [])

  inbox = ensure_tag.(demo_scope, "inbox", 7)
  side_project = ensure_tag.(demo_scope, "side project", 90)
  reading_list = ensure_tag.(alice_scope, "reading list", 21)

  # Refresh scopes after possible default_tag clears above.
  demo = Accounts.get_user!(demo.id)
  alice = Accounts.get_user!(alice.id)
  admin = Accounts.get_user!(admin.id)
  demo_scope = Scope.for_user(demo)
  alice_scope = Scope.for_user(alice)
  admin_scope = Scope.for_user(admin)

  saved = tag_by_name.(demo_scope, "saved for later")
  read_later = tag_by_name.(demo_scope, "read later")
  watch_later = tag_by_name.(demo_scope, "watch later")

  {:ok, alice} =
    Accounts.update_user_settings(alice, %{
      auto_mark_viewed_on_open: true,
      default_tags_enabled: true,
      default_tag_id: reading_list.id
    })

  alice_scope = Scope.for_user(alice)

  now = DateTime.utc_now(:second)
  expires_soon = DateTime.add(now, 12, :hour)
  expires_this_week = DateTime.add(now, 3, :day)

  # --- Demo user links (primary library for product demos) -------------------

  demo_links = [
    %{
      url: "https://phoenixframework.org/",
      title: "Phoenix Framework",
      description: "Peace of mind from prototype to production.",
      favicon_url: "https://phoenixframework.org/favicon.ico",
      note: "Docs home — start here for LiveView.",
      tags: [read_later],
      indexed: true,
      viewed: false
    },
    %{
      url: "https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html",
      title: "Phoenix.LiveView",
      description: "LiveView — interactive, real-time apps without writing JS.",
      tags: [read_later, saved],
      indexed: true,
      viewed: false
    },
    %{
      url: "https://elixir-lang.org/",
      title: "Elixir",
      description: "A dynamic, functional language for building scalable applications.",
      tags: [saved],
      indexed: true,
      viewed: false
    },
    %{
      url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
      title: "Never Gonna Give You Up",
      description: "Official music video.",
      duration_seconds: 213,
      tags: [watch_later],
      indexed: true,
      viewed: false
    },
    %{
      url: "https://vimeo.com/148751763",
      title: "The Mountain",
      description: "Nature short — duration preview sample.",
      duration_seconds: 502,
      note: "Check duration chip on the card.",
      tags: [watch_later, inbox],
      indexed: true,
      viewed: false
    },
    %{
      url: "https://github.com/phoenixframework/phoenix",
      title: "phoenixframework/phoenix",
      description: "Peace of mind from prototype to production.",
      tags: [side_project, saved],
      indexed: true,
      viewed: false
    },
    %{
      url: "https://news.ycombinator.com/",
      title: "Hacker News",
      description: "News for hackers.",
      tags: [inbox],
      # Marked viewed for filter demos; in :dev purged after :viewed_grace_seconds (5s).
      indexed: true,
      viewed: true
    },
    %{
      url: "https://expiring-soon.example.com/article",
      title: "Expiring within 48 hours",
      description: "Stats / filter scenario: expiring soon.",
      tags: [inbox],
      indexed: true,
      viewed: false,
      expires_overrides: %{"inbox" => expires_soon}
    },
    %{
      url: "https://expiring-week.example.com/article",
      title: "Expiring later this week",
      description: "Stats / filter scenario: about to expire.",
      tags: [read_later],
      indexed: true,
      viewed: false,
      expires_overrides: %{"read later" => expires_this_week}
    },
    %{
      url: "https://pending-index.example.com/new",
      title: "Awaiting metadata",
      note: "Not indexed yet — pending index (next attempt deferred).",
      tags: [inbox],
      pending: true,
      viewed: false
    },
    %{
      url: "https://failed-index.example.com/retry",
      title: nil,
      tags: [saved],
      indexed: false,
      failed: true,
      viewed: false
    },
    %{
      url: "https://gave-up.example.com/dead",
      title: nil,
      tags: [saved],
      indexed: false,
      gave_up: true,
      viewed: false
    },
    %{
      url: "https://multi-tag.example.com/post",
      title: "Multi-tagged bookmark",
      description: "Has several tags for filter / merge demos.",
      note: "Try filtering by more than one tag.",
      tags: [inbox, read_later, side_project],
      indexed: true,
      viewed: false
    },
    %{
      url: "https://tailwindcss.com/docs",
      title: "Tailwind CSS Docs",
      description: "Rapidly build modern websites without ever leaving your HTML.",
      tags: [read_later],
      indexed: true,
      viewed: false
    }
  ]

  Enum.each(demo_links, &seed_link.(demo_scope, &1))

  # --- Alice (preferences + lighter library) ---------------------------------

  alice_saved = tag_by_name.(alice_scope, "saved for later")

  alice_links = [
    %{
      url: "https://dashbit.co/blog",
      title: "Dashbit Blog",
      description: "Elixir / NX / Livebook writing.",
      tags: [reading_list],
      indexed: true,
      viewed: false
    },
    %{
      url: "https://www.erlang.org/",
      title: "Erlang/OTP",
      tags: [alice_saved],
      indexed: true,
      viewed: false
    }
  ]

  Enum.each(alice_links, &seed_link.(alice_scope, &1))

  # --- Admin (sparse set for multi-user / admin panel demos) -----------------

  admin_saved = tag_by_name.(admin_scope, "saved for later")

  admin_links = [
    %{
      url: "https://github.com/ojizero/liminal",
      title: "Liminal repository",
      description: "Self-hosted link manager.",
      tags: [admin_saved],
      indexed: true,
      viewed: false
    },
    %{
      url: "https://admin-only.example.com/notes",
      title: "Admin scratch pad",
      note: "Visible only when logged in as admin.",
      tags: [admin_saved],
      indexed: true,
      viewed: false
    }
  ]

  Enum.each(admin_links, &seed_link.(admin_scope, &1))

  link_count = Repo.aggregate(Link, :count)
  user_count = Repo.aggregate(User, :count)

  IO.puts("""
  Demo seed complete.
    Users:  #{user_count}  |  Links: #{link_count}
    Login:  admin / #{password}   (admin)
            demo  / #{password}   (primary demo library)
            alice / #{password}   (default tag + auto-mark-viewed)
            disabled / #{password} (disabled — cannot sign in)
            invited                 (no password — invite / reset flow)
  """)
after
  Application.put_env(:liminal, :start_indexer, previous_indexer)
end
