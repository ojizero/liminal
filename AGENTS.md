# Implementation guide

This file records repository-specific implementation rules for human and automated contributors. Setup, commands, and pull-request policy are in [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).

## Required checks

- Run `mix precommit` after changes and resolve every issue.
- Use the Erlang and Elixir versions pinned in `.mise.toml`; run `mise install` after a version change.
- Use Conventional Commits as documented in `docs/CONTRIBUTING.md`.

## Architecture

- `Liminal.Accounts` owns users, authentication, authorization scopes, and account administration.
- `Liminal.Links` owns links, tags, search, statistics, indexing, cleanup, and reindexing.
- Context functions that access user data take `current_scope` first and filter through `current_scope.user`.
- Templates access the signed-in user as `@current_scope.user`; there is no `@current_user` assign.
- Use `Req` for HTTP. Do not add another HTTP client.

## Routing and authentication

Authentication is enforced in `lib/liminal_web/router.ex`. Add routes to the existing matching scope; never duplicate a `live_session` name.

### Public or conditionally public LiveViews

Place login, registration, and password-reset routes in:

```elixir
scope "/", LiminalWeb do
  pipe_through [:browser]

  live_session :current_user,
    on_mount: [{LiminalWeb.UserAuth, :mount_current_scope}] do
    live "/public-path", PublicLive
  end
end
```

The `:browser` pipeline assigns `current_scope`. Registration and login perform their authenticated-user redirects in their LiveView mounts; this project has no `redirect_if_user_is_authenticated` plug.

### Authenticated LiveViews

Place signed-in routes in the existing root scope and session:

```elixir
scope "/", LiminalWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :require_authenticated_user,
    on_mount: [{LiminalWeb.UserAuth, :require_authenticated}] do
    live "/path", FeatureLive
  end
end
```

Authenticated controller routes use the same `[:browser, :require_authenticated_user]` pipeline.

### Admin LiveViews

Place admin routes in the existing admin scope and session:

```elixir
scope "/admin", LiminalWeb.Admin do
  pipe_through [:browser, :require_authenticated_user, :require_admin_user]

  live_session :require_admin,
    on_mount: [{LiminalWeb.UserAuth, :require_admin}] do
    live "/path", FeatureLive
  end
end
```

The scope already aliases `LiminalWeb.Admin`; do not repeat that prefix in route modules.

## Phoenix and LiveView

- Start every LiveView template with `<Layouts.app flash={@flash} current_scope={@current_scope}>`.
- Keep `<.flash_group>` inside `layouts.ex`.
- Use `<.icon>` for Heroicons and `<.input>` for supported form fields.
- Give forms, controls, collection parents, and other tested elements stable unique DOM IDs.
- Use `<.link navigate={...}>`, `<.link patch={...}>`, `push_navigate/2`, and `push_patch/2`; deprecated live redirect helpers are not allowed.
- Prefer LiveViews and function components. Add a LiveComponent only when isolated state or update boundaries justify it.

### Forms

Build forms in the LiveView with `to_form/2` and render them with `<.form for={@form}>`.

```elixir
socket = assign(socket, :form, changeset |> to_form())
```

```heex
<.form for={@form} id="feature-form" phx-submit="save">
  <.input field={@form[:name]} type="text" />
</.form>
```

Do not pass a changeset directly to the template, use `<.form let={f}>`, or access a changeset with bracket syntax.

### Collections and streams

Use LiveView streams for UI collections that are inserted, updated, reset, or deleted.

- The parent needs a stable ID and `phx-update="stream"`.
- Render `@streams.name` and use each stream-generated ID on its child.
- Refetch and call `stream(..., reset: true)` when filtering.
- Track counts and empty-state metadata in separate assigns; streams are not enumerable.
- Reinsert streamed records when another assign changes their rendered content.
- Do not use deprecated `phx-update="append"` or `"prepend"`.

### HEEx

- Use `~H` or `.html.heex`, never `~E`.
- Use `{...}` for values and attributes; use `<%= ... %>` for block constructs in tag bodies.
- Use `<%= for item <- @items do %>`, not `Enum.each`.
- Use `<%!-- --%>` for template comments.
- Use list syntax for multiple or conditional classes.
- Add `phx-no-curly-interpolation` to code blocks containing literal JavaScript-style braces.
- Elixir has `if/else`, not `else if`; use `cond` or `case` for multiple branches.

## JavaScript and CSS

- Keep the Tailwind v4 imports in `assets/css/app.css`:

```css
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/liminal_web";
```

- Use Tailwind utilities, daisyUI primitives, and focused custom CSS. Do not use `@apply`.
- Only `app.js` and `app.css` are application bundles. Import vendored dependencies there; do not add external script or stylesheet tags to layouts.
- Prefer pure HEEx, then `Phoenix.LiveView.JS`, then JavaScript hooks.
- Raw inline scripts in HEEx are invalid. Use a colocated hook whose name starts with `.` or an external hook in `assets/js/`.
- Every `phx-hook` needs a unique DOM ID. Add `phx-update="ignore"` when the hook owns its DOM.
- Rebind or return the socket from `push_event/3`.

## Elixir and Ecto

- Access list elements with pattern matching, `Enum.at/2`, or `List`, not bracket indexing.
- Bind the result of `if`, `case`, and `cond` when it changes the value used afterward.
- Keep one module per file.
- Access structs with fields or their APIs. For changesets, use `Ecto.Changeset.get_field/2`.
- Do not convert user input with `String.to_atom/1`.
- Predicate functions end in `?`; reserve `is_*` names for guards.
- Name OTP supervisors and registries in child specs.
- Use `Task.async_stream/3` with back-pressure for concurrent enumeration; use `timeout: :infinity` when work has no valid fixed timeout.
- Preload associations before templates access them.
- Schema text columns still use `field ..., :string`.
- Do not pass `allow_nil` to `validate_number/3`.
- Never cast ownership fields such as `user_id`; set them from the authenticated scope.
- Generate migrations with `mix ecto.gen.migration descriptive_name`.

## Testing

- Use `start_supervised!/1` for test processes.
- Do not synchronize with `Process.sleep/1` or assert with `Process.alive?/1`. Monitor termination, assert messages, or call `_ = :sys.get_state(pid)`.
- LiveView tests use `Phoenix.LiveViewTest` and stable element IDs through `element/2`, `has_element?/2`, `render_change/2`, and `render_submit/2`.
- Assert outcomes and DOM structure, not raw rendered HTML strings or mutable copy.
- Use `LazyHTML` to inspect a narrow selector when debugging rendered markup.
- Use `Req.Test` plugs for outbound requests.
- Run the narrow affected tests while iterating, then `mix precommit`.

## Documentation

- Update documentation in the same change when behavior, configuration, setup, operations, or release workflow changes.
- Keep `README.md` as the product and setup overview. Put deployment details in `docs/DEPLOYMENT.md`, contribution policy in `docs/CONTRIBUTING.md`, and release policy in `docs/RELEASE.md`.
- Document current behavior and constraints. Do not include aspirational claims, duplicated framework tutorials, or commands that have not been checked against repository scripts.
