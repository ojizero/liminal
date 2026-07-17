defmodule Liminal.Links.ReindexJobs do
  @moduledoc """
  Reindex job lifecycle and authorization.
  """

  alias Liminal.Accounts.Scope
  alias Liminal.Links.Reindex

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
    with status <- Reindex.status(),
         true <- can_cancel_reindex?(scope, status) do
      Reindex.cancel()
    else
      false -> {:error, :unauthorized}
    end
  end

  @doc "Returns whether the current scope can cancel the active reindex job."
  def can_cancel_reindex?(scope, %{active: true, requested_by: requested_by}) do
    Scope.admin?(scope) or scope.user.id == requested_by
  end

  def can_cancel_reindex?(_scope, _status), do: false

  def ensure_admin!(scope) do
    unless Scope.admin?(scope), do: raise("admin required")
  end
end
