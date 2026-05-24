defmodule Liminal.RetryTest do
  use ExUnit.Case, async: true

  alias Liminal.Retry

  setup do
    on_exit(fn ->
      Application.delete_env(:liminal, Retry)
    end)

    :ok
  end

  describe "delay_seconds/1" do
    test "exponential backoff from base delay" do
      assert Retry.delay_seconds(1) == 300
      assert Retry.delay_seconds(2) == 600
      assert Retry.delay_seconds(3) == 1200
    end

    test "caps delay at max_delay_seconds" do
      Application.put_env(:liminal, Retry,
        max_attempts: 20,
        base_delay_seconds: 300,
        max_delay_seconds: 3600
      )

      assert Retry.delay_seconds(20) == 3600
    end
  end

  describe "next_attempt_at/2" do
    test "adds delay to the given timestamp" do
      now = ~U[2026-05-24 12:00:00Z]

      assert Retry.next_attempt_at(1, now) == ~U[2026-05-24 12:05:00Z]
    end
  end

  describe "give_up?/1" do
    test "returns false below max attempts" do
      refute Retry.give_up?(9)
    end

    test "returns true at max attempts" do
      assert Retry.give_up?(10)
    end

    test "respects configured max attempts" do
      Application.put_env(:liminal, Retry, max_attempts: 3)

      refute Retry.give_up?(2)
      assert Retry.give_up?(3)
    end
  end

  describe "eligible?/2" do
    test "indexed links are not eligible" do
      link = %Liminal.Links.Link{indexed_at: DateTime.utc_now(:second)}

      refute Retry.eligible?(link)
    end

    test "gave-up links are not eligible" do
      link = %Liminal.Links.Link{index_gave_up_at: DateTime.utc_now(:second)}

      refute Retry.eligible?(link)
    end

    test "links with future next attempt are not eligible" do
      now = ~U[2026-05-24 12:00:00Z]
      link = %Liminal.Links.Link{index_next_attempt_at: ~U[2026-05-24 13:00:00Z]}

      refute Retry.eligible?(link, now)
    end

    test "unindexed links without schedule are eligible" do
      link = %Liminal.Links.Link{}

      assert Retry.eligible?(link)
    end

    test "links with past next attempt are eligible" do
      now = ~U[2026-05-24 12:00:00Z]
      link = %Liminal.Links.Link{index_next_attempt_at: ~U[2026-05-24 11:00:00Z]}

      assert Retry.eligible?(link, now)
    end
  end
end
