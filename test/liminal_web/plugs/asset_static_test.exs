defmodule LiminalWeb.Plugs.AssetStaticTest do
  # Not async: mutates the global :assets_dir application env.
  use ExUnit.Case, async: false

  alias LiminalWeb.Plugs.AssetStatic

  test "init serves assets from configured assets_dir" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "liminal_asset_static_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)
    Application.put_env(:liminal, :assets_dir, tmp_dir)

    on_exit(fn ->
      Application.delete_env(:liminal, :assets_dir)
      File.rm_rf(tmp_dir)
    end)

    opts = AssetStatic.init([])

    assert opts[:from] == tmp_dir
    assert opts[:at] == ["assets"]
  end
end
