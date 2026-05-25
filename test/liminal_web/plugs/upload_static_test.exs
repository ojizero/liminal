defmodule LiminalWeb.Plugs.UploadStaticTest do
  use ExUnit.Case, async: true

  alias LiminalWeb.Plugs.UploadStatic

  test "init serves uploads from configured upload_static_from" do
    tmp_from =
      Path.join(
        System.tmp_dir!(),
        "liminal_upload_static_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(tmp_from, "images"))
    Application.put_env(:liminal, :upload_static_from, tmp_from)

    on_exit(fn ->
      Application.delete_env(:liminal, :upload_static_from)
      File.rm_rf(tmp_from)
    end)

    opts = UploadStatic.init([])

    assert opts[:from] == tmp_from
    assert opts[:at] == ["uploads"]
  end
end
