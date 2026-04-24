defmodule Liminal.Links.JanitorTest do
  use Liminal.DataCase

  alias Liminal.Links.Janitor
  alias Liminal.Links.LinkTag

  describe "schedule_cleanup/1" do
    test "no-op when link_tag has nil expires_at" do
      lt = %LinkTag{id: Ecto.UUID.generate(), expires_at: nil}
      assert :ok = Janitor.schedule_cleanup(lt)
    end

    test "accepts a link_tag with expires_at" do
      lt = %LinkTag{
        id: Ecto.UUID.generate(),
        expires_at: DateTime.add(DateTime.utc_now(:second), 300, :second)
      }

      assert :ok = Janitor.schedule_cleanup(lt)
    end
  end
end
