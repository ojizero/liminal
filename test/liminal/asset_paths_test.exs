defmodule Liminal.AssetPathsTest do
  # Not async: mutates the global :assets_dir application env.
  use ExUnit.Case, async: false

  alias Liminal.AssetPaths

  @user_id "550e8400-e29b-41d4-a716-446655440000"

  setup do
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

    %{tmp_dir: tmp_dir}
  end

  test "file_path resolves user-scoped paths under assets_dir", %{tmp_dir: tmp_dir} do
    assert AssetPaths.file_path("assets/#{@user_id}/abc.png") ==
             Path.join([tmp_dir, @user_id, "abc.png"])
  end

  test "file_path resolves legacy flat paths under assets_dir", %{tmp_dir: tmp_dir} do
    assert AssetPaths.file_path("assets/abc.png") == Path.join(tmp_dir, "abc.png")
  end

  test "relative_path includes user id and filename" do
    assert AssetPaths.relative_path(@user_id, "abc.png") == "assets/#{@user_id}/abc.png"
  end

  test "owned_by_user? matches user-scoped paths" do
    assert AssetPaths.owned_by_user?("assets/#{@user_id}/abc.png", @user_id)
    refute AssetPaths.owned_by_user?("assets/other-user/abc.png", @user_id)
    refute AssetPaths.owned_by_user?("assets/abc.png", @user_id)
  end

  test "parse_relative_path rejects path traversal" do
    assert AssetPaths.parse_relative_path("assets/#{@user_id}/../secret.png") == :error
    assert AssetPaths.parse_relative_path("assets/../secret.png") == :error
  end

  test "valid_filename? rejects unsafe filenames" do
    assert AssetPaths.valid_filename?("abc.png")
    refute AssetPaths.valid_filename?("../secret.png")
    refute AssetPaths.valid_filename?("nested/file.png")
  end

  test "ensure_assets_dir! creates assets_dir", %{tmp_dir: tmp_dir} do
    AssetPaths.ensure_assets_dir!()
    assert File.dir?(tmp_dir)
  end

  test "ensure_user_assets_dir! creates user subdirectory", %{tmp_dir: tmp_dir} do
    AssetPaths.ensure_user_assets_dir!(@user_id)
    assert File.dir?(Path.join(tmp_dir, @user_id))
  end
end
