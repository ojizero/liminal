defmodule Liminal.AssetPathsTest do
  # Not async: mutates the global :assets_dir application env.
  use ExUnit.Case, async: false

  alias Liminal.AssetPaths

  test "file_path resolves basename under assets_dir" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "liminal_asset_paths_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:liminal, :assets_dir, tmp_dir)

    on_exit(fn ->
      Application.delete_env(:liminal, :assets_dir)
      File.rm_rf(tmp_dir)
    end)

    assert AssetPaths.file_path("assets/abc.png") == Path.join(tmp_dir, "abc.png")
  end

  test "ensure_assets_dir! creates assets_dir" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "liminal_asset_paths_mkdir_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:liminal, :assets_dir, tmp_dir)

    on_exit(fn ->
      Application.delete_env(:liminal, :assets_dir)
      File.rm_rf(tmp_dir)
    end)

    AssetPaths.ensure_assets_dir!()
    assert File.dir?(tmp_dir)
  end
end
