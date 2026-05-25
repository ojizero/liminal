defmodule Liminal.UploadPathsTest do
  use ExUnit.Case, async: true

  alias Liminal.UploadPaths

  test "file_path resolves basename under upload_dir" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "liminal_upload_paths_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:liminal, :upload_dir, tmp_dir)

    on_exit(fn ->
      Application.delete_env(:liminal, :upload_dir)
      File.rm_rf(tmp_dir)
    end)

    assert UploadPaths.file_path("uploads/images/abc.png") == Path.join(tmp_dir, "abc.png")
  end

  test "ensure_upload_dir! creates upload_dir" do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "liminal_upload_paths_mkdir_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:liminal, :upload_dir, tmp_dir)

    on_exit(fn ->
      Application.delete_env(:liminal, :upload_dir)
      File.rm_rf(tmp_dir)
    end)

    UploadPaths.ensure_upload_dir!()
    assert File.dir?(tmp_dir)
  end
end
