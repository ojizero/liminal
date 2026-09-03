defmodule Liminal.Links do
  @moduledoc """
  Links, tags, and link-tag associations for a user.

  Mutations broadcast on `"user_links:<user_id>"` so LiveViews stay in sync across tabs.
  """

  alias Liminal.Accounts.Scope

  alias Liminal.Links.{
    Events,
    Expiration,
    ExpiryPause,
    Indexing,
    Mutations,
    Query,
    Reindex,
    Stats,
    Tagging,
    Tags,
    Viewed
  }

  ## PubSub

  @doc "Subscribe the calling process to link events for the given user."
  defdelegate subscribe_links(scope), to: Events

  @doc "Subscribe the calling process to expiry pause changes for the given user."
  defdelegate subscribe_expiry_pause(scope), to: Events

  ## Default tags

  @doc "Creates default tags for a new user."
  defdelegate create_default_tags(user_id), to: Tags

  ## Tags CRUD

  @doc """
  Lists all tags for the given user, ordered by name.
  """
  defdelegate list_tags(scope), to: Tags

  @doc """
  Gets a single tag by id, scoped to the user.

  Raises `Ecto.NoResultsError` if not found.
  """
  defdelegate get_tag!(scope, id), to: Tags

  @doc """
  Creates a tag for the given user.
  """
  defdelegate create_tag(scope, attrs), to: Tags

  @doc """
  Updates a tag. Verifies ownership via pattern match.
  """
  defdelegate update_tag(scope, tag, attrs), to: Tags

  @doc """
  Deletes a tag. Verifies ownership via pattern match.
  """
  defdelegate delete_tag(scope, tag), to: Tags

  @doc """
  Returns a changeset for tracking tag changes.
  """
  defdelegate change_tag(tag, attrs \\ %{}), to: Tags

  ## Links CRUD

  @doc """
  Lists links for the given user with preloaded tags.

  ## Options

    * `:filter` - `:unviewed` (default), `:all`, or `:viewed`
    * `:sort` - `:time_added_desc` (default), `:time_added_asc`, or `:expiring_soon`
    * `:tag_ids` - list of tag IDs to filter by (default `[]` = no tag filter)
    * `:query` - fuzzy text search across title, note, description, and URL (default `""`)

  """
  defdelegate list_links(scope, opts \\ []), to: Query

  @doc """
  Returns a random link for the given user.

  Picks uniformly from all saved links regardless of viewed state or tags.
  """
  defdelegate random_link(scope), to: Query

  @doc "Fetches a user's link by id with tags preloaded; raises when missing."
  defdelegate get_link!(scope, id), to: Query

  @doc "Finds a user's link by exact URL, or `nil` if none exists."
  defdelegate find_link_by_url(scope, url), to: Query

  @doc """
  Updates a link. Verifies ownership via pattern match.

  When the URL changes, clears indexed metadata and re-queues indexing.
  """
  defdelegate update_link(scope, link, attrs), to: Mutations

  @doc """
  Deletes a link. Verifies ownership via pattern match.
  """
  defdelegate delete_link(scope, link), to: Mutations

  @doc "Returns a link changeset for create/edit forms."
  defdelegate change_link(link, attrs \\ %{}), to: Mutations

  @doc """
  Creates a link for the given user.

  The 3-arity version tags it with the given tag IDs atomically using
  `Ecto.Multi`. The 2-arity version (without tag_ids) always returns
  `{:error, :no_tags}` since links must have at least one tag.
  """
  defdelegate create_link(scope, attrs, tag_ids), to: Mutations

  defdelegate create_link(scope, attrs), to: Mutations

  ## Indexing

  @doc """
  Returns links eligible for indexing retry.

  Uses `indexed_at IS NULL AND inserted_at < now - older_than_minutes` to avoid
  racing with in-progress indexing tasks. Respects backoff via `index_next_attempt_at`
  and excludes links where the Janitor has given up (`index_gave_up_at`).
  """
  defdelegate list_index_retry_candidates(opts \\ []), to: Indexing

  @doc "Legacy alias for `list_index_retry_candidates/1`."
  defdelegate list_unindexed_links(opts \\ []), to: Indexing

  @doc """
  Updates a link's metadata fields from the indexer.
  Only sets title from metadata if the user hasn't already provided one.
  """
  defdelegate update_link_metadata(link, metadata), to: Indexing

  @doc """
  Records a failed indexing attempt and schedules the next retry or gives up.
  """
  defdelegate record_index_failure(link), to: Indexing

  @doc "Resets indexing retry fields for a link."
  defdelegate reset_index_retry(link), to: Indexing

  @doc """
  Resets retry state and re-queues indexing for a link via the reindex coordinator.
  """
  defdelegate retry_indexing(scope, link), to: Indexing

  @doc """
  Returns link IDs for a reindex job scope.

  ## Scopes

    * `{:link, link_id}`
    * `{:user, user_id, mode}` where `mode` is `:all` or `:failed`
    * `{:instance, mode}` where `mode` is `:all` or `:failed`
  """
  defdelegate list_reindex_link_ids(scope), to: Indexing

  @doc """
  Resets a link so it can be reindexed.

  `:all` clears stored metadata and preview images; `:failed` only resets retry state.
  """
  defdelegate prepare_link_for_reindex(link, mode), to: Indexing

  @doc "Queues a single link for metadata indexing."
  defdelegate queue_index(link_id, user_id), to: Indexing

  ## Stats

  @doc "Returns instance-wide link statistics. Admin only."
  def instance_stats(scope) do
    ensure_admin!(scope)
    Stats.instance_stats()
  end

  @doc "Returns per-user link statistics."
  defdelegate user_stats(scope), to: Stats

  ## Reindex

  @doc "Returns the current reindex job state."
  def reindex_status do
    Reindex.status()
  end

  @doc "Starts an instance-wide reindex job. Admin only."
  def start_instance_reindex(scope, mode) when mode in [:all, :failed] do
    ensure_admin!(scope)
    Reindex.start_job({:instance, mode}, requested_by: scope.user.id)
  end

  @doc "Starts a user-scoped reindex job for the current user."
  def start_user_reindex(scope, mode) when mode in [:all, :failed] do
    Reindex.start_job({:user, scope.user.id, mode}, requested_by: scope.user.id)
  end

  @doc "Cancels the current reindex job when permitted."
  def cancel_reindex(scope) do
    status = Reindex.status()

    if can_cancel_reindex?(scope, status) do
      Reindex.cancel()
    else
      {:error, :unauthorized}
    end
  end

  @doc "Returns whether the current scope can cancel the active reindex job."
  def can_cancel_reindex?(scope, %{active: true, requested_by: requested_by}) do
    Scope.admin?(scope) or scope.user.id == requested_by
  end

  def can_cancel_reindex?(_scope, _status), do: false

  ## Viewed state

  @doc "Marks a link as viewed now."
  defdelegate mark_viewed(scope, link), to: Viewed

  @doc "Clears the viewed timestamp on a link."
  defdelegate mark_unviewed(scope, link), to: Viewed

  ## Tagging

  @doc """
  Merges tags onto an existing link.

  Tags included in `tag_ids` are added if new, or have their expiry refreshed
  if already assigned. Tags on the link that are not in `tag_ids` are unchanged.
  """
  defdelegate merge_link_tags(scope, link, tag_ids), to: Tagging

  @doc """
  Tags a link with a tag. Computes `expires_at` from the tag's
  `expires_in_days`. Uses `on_conflict: :nothing` for idempotency.
  """
  defdelegate tag_link(scope, link, tag), to: Tagging

  @doc """
  Removes a link_tag by ID. Idempotent — no-op if already gone.
  """
  defdelegate untag_link(link_tag_id), to: Tagging

  @doc """
  Removes a link_tag and deletes the owning link if it has no remaining
  tags. Returns `{:ok, :link_deleted}` or `{:ok, :tag_removed}`.
  """
  defdelegate cleanup_link(link_tag_id), to: Tagging

  @doc """
  Scoped version — looks up the link_tag from the link/tag pair,
  verifies ownership, then delegates to `cleanup_link/1`.
  """
  defdelegate cleanup_link(scope, link, tag), to: Tagging

  ## Expiry cleanup

  @doc """
  Returns when a link expires, on the wall clock.

  For unviewed links, this is the latest tag `expires_at`. For viewed links,
  this is `viewed_at` plus the configured grace period (`:viewed_grace_seconds`,
  default 1 day).

  Pass the owner's pause (a scope, user, or `nil`) as the second argument so a
  running pause is taken into account.
  """
  defdelegate link_expires_at(link, pause \\ nil), to: Expiration

  @doc """
  Deletes links viewed longer than the configured grace period (default 1 day;
  see `:viewed_grace_seconds` application env) with all their tags, then removes
  expired link_tags and deletes orphaned links. Used by the Janitor's periodic sweep.

  Settles lapsed expiry pauses first and skips users who are still paused.
  """
  defdelegate cleanup_expired(), to: Expiration

  ## Expiry pause

  @doc """
  Pauses expiry counting for the scope's user for `days`, up to
  `max_expiry_pause_days/0`.

  While paused nothing expires and every countdown holds where it is. Calling this
  again re-times a running pause from its original start rather than restarting it.
  Returns `{:error, :invalid_duration}` for a length outside the allowed range.
  """
  defdelegate pause_expiries(scope, days), to: ExpiryPause, as: :pause

  @doc """
  Resumes expiry counting for the scope's user, picking every countdown up from
  where it stopped.
  """
  defdelegate resume_expiries(scope), to: ExpiryPause, as: :resume

  @doc "Returns whether expiries are currently paused for the given scope or user."
  defdelegate expiry_paused?(subject), to: ExpiryPause, as: :paused?

  @doc "Returns the pause window for the given scope or user, or `nil` when running."
  defdelegate expiry_pause_state(subject), to: ExpiryPause, as: :state

  @doc "Returns when the pause ends for the given scope or user, or `nil`."
  defdelegate expiry_pause_resumes_at(subject), to: ExpiryPause, as: :resumes_at

  @doc "Returns the pause lengths offered in settings as `{label, days}` pairs."
  defdelegate expiry_pause_duration_options(), to: ExpiryPause, as: :duration_options

  @doc "Returns the pause length preselected in settings, in days."
  defdelegate default_expiry_pause_days(), to: ExpiryPause, as: :default_pause_days

  @doc "Returns the longest pause a user may request, in days."
  defdelegate max_expiry_pause_days(), to: ExpiryPause, as: :max_pause_days

  @doc """
  Converts a stored expiry deadline to the wall-clock time it now falls on, given
  the owner's pause.
  """
  defdelegate expiry_wall_clock(expires_at, subject), to: ExpiryPause, as: :wall_clock

  defp ensure_admin!(scope) do
    unless Scope.admin?(scope), do: raise("admin required")
  end
end
