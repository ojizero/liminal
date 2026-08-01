defmodule Liminal.Retry do
  @moduledoc """
  Exponential backoff utilities for scheduling retries.

  Configured via application env:

      config :liminal, Liminal.Retry,
        max_attempts: 10,
        base_delay_seconds: 300,
        max_delay_seconds: 86_400
  """

  @default_max_attempts 10
  @default_base_delay_seconds 300
  @default_max_delay_seconds 86_400

  @doc """
  Returns retry configuration as a keyword list.
  """
  def config do
    [
      max_attempts: @default_max_attempts,
      base_delay_seconds: @default_base_delay_seconds,
      max_delay_seconds: @default_max_delay_seconds
    ]
    |> Keyword.merge(Application.get_env(:liminal, __MODULE__, []))
  end

  @doc """
  Delay in seconds before the next attempt after `attempt_count` failures.
  """
  def delay_seconds(attempt_count) when is_integer(attempt_count) and attempt_count > 0 do
    config = config()
    base = Keyword.fetch!(config, :base_delay_seconds)
    max_delay = Keyword.fetch!(config, :max_delay_seconds)

    min(max_delay, base * Integer.pow(2, attempt_count - 1))
  end

  @doc """
  Returns the UTC datetime when the next attempt should occur.
  """
  def next_attempt_at(attempt_count, now \\ DateTime.utc_now(:second)) do
    DateTime.add(now, delay_seconds(attempt_count), :second)
  end

  @doc """
  Returns true when `attempt_count` has reached the configured maximum.
  """
  def give_up?(attempt_count) when is_integer(attempt_count) do
    attempt_count >= Keyword.fetch!(config(), :max_attempts)
  end
end
