defmodule Liminal.Accounts.Scope do
  @moduledoc """
  Caller identity threaded through contexts, LiveViews, and PubSub.

  Authenticated routes assign `%Scope{user: user}` so queries and broadcasts
  stay scoped to the current user.
  """

  alias Liminal.Accounts.User

  defstruct user: nil

  @doc false
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc """
  Returns `true` if the scope belongs to an admin user.
  """
  def admin?(%__MODULE__{user: %User{role: "admin"}}), do: true
  def admin?(_), do: false
end
