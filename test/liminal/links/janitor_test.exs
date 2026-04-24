defmodule Liminal.Links.JanitorTest do
  use Liminal.DataCase

  alias Liminal.Links.Janitor
  alias Liminal.Links.LinkCategory

  describe "schedule_cleanup/1" do
    test "no-op when link_category has nil expires_at" do
      lc = %LinkCategory{id: Ecto.UUID.generate(), expires_at: nil}
      assert :ok = Janitor.schedule_cleanup(lc)
    end

    test "accepts a link_category with expires_at" do
      lc = %LinkCategory{
        id: Ecto.UUID.generate(),
        expires_at: DateTime.add(DateTime.utc_now(:second), 300, :second)
      }

      assert :ok = Janitor.schedule_cleanup(lc)
    end
  end
end
