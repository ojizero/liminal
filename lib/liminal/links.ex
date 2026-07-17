defmodule Liminal.Links do
  @moduledoc """
  Facade for links, tags, link-tag associations, indexing, and expiration.

  Mutations broadcast on `"user_links:<user_id>"` so LiveViews stay in sync
  across tabs. Implementations live in focused modules under `Liminal.Links.*`.
  """

  alias Liminal.Links.{
    Commands,
    Expiration,
    Indexing,
    LinkTags,
    PubSub,
    Query,
    ReindexJobs,
    Stats,
    Tags,
    Viewed
  }

  defdelegate subscribe_links(scope), to: PubSub

  defdelegate create_default_tags(user_id), to: Tags
  defdelegate list_tags(scope), to: Tags
  defdelegate get_tag!(scope, id), to: Tags
  defdelegate create_tag(scope, attrs), to: Tags
  defdelegate update_tag(scope, tag, attrs), to: Tags
  defdelegate delete_tag(scope, tag), to: Tags
  defdelegate change_tag(tag, attrs \\ %{}), to: Tags

  defdelegate list_links(scope, opts \\ []), to: Query
  defdelegate random_link(scope), to: Query
  defdelegate get_link!(scope, id), to: Query
  defdelegate find_link_by_url(scope, url), to: Query

  defdelegate list_index_retry_candidates(opts \\ []), to: Indexing
  defdelegate list_unindexed_links(opts \\ []), to: Indexing
  defdelegate list_reindex_link_ids(scope), to: Indexing
  defdelegate prepare_link_for_reindex(link, mode), to: Indexing
  defdelegate queue_index(link_id, user_id), to: Indexing
  defdelegate update_link_metadata(link, metadata), to: Indexing
  defdelegate record_index_failure(link), to: Indexing
  defdelegate reset_index_retry(link), to: Indexing
  defdelegate retry_indexing(scope, link), to: Indexing

  defdelegate reindex_status(), to: ReindexJobs
  defdelegate start_instance_reindex(scope, mode), to: ReindexJobs
  defdelegate start_user_reindex(scope, mode), to: ReindexJobs
  defdelegate cancel_reindex(scope), to: ReindexJobs
  defdelegate can_cancel_reindex?(scope, status), to: ReindexJobs

  defdelegate create_link(scope, attrs), to: Commands
  defdelegate create_link(scope, attrs, tag_ids), to: Commands
  defdelegate update_link(scope, link, attrs), to: Commands
  defdelegate delete_link(scope, link), to: Commands
  defdelegate change_link(link, attrs \\ %{}), to: Commands

  defdelegate merge_link_tags(scope, link, tag_ids), to: LinkTags
  defdelegate tag_link(scope, link, tag), to: LinkTags
  defdelegate untag_link(link_tag_id), to: LinkTags
  defdelegate cleanup_link(link_tag_id), to: LinkTags
  defdelegate cleanup_link(scope, link, tag), to: LinkTags

  defdelegate mark_viewed(scope, link), to: Viewed
  defdelegate mark_unviewed(scope, link), to: Viewed

  defdelegate link_expires_at(link), to: Expiration
  defdelegate cleanup_expired(), to: Expiration

  def instance_stats(scope) do
    ReindexJobs.ensure_admin!(scope)
    Stats.instance_stats()
  end

  defdelegate user_stats(scope), to: Stats
end
