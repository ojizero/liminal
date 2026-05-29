defmodule LiminalWeb.AssetControllerTest do
  use LiminalWeb.ConnCase, async: false

  import Liminal.AccountsFixtures

  setup %{conn: conn} do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "liminal_asset_controller_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:liminal, :assets_dir, tmp_dir)

    on_exit(fn ->
      Application.delete_env(:liminal, :assets_dir)
      File.rm_rf(tmp_dir)
    end)

    %{conn: conn, tmp_dir: tmp_dir}
  end

  setup :register_and_log_in_user

  test "serves owned asset to authenticated user", %{conn: conn, user: user, tmp_dir: tmp_dir} do
    filename = "preview.png"
    user_dir = Path.join(tmp_dir, user.id)
    File.mkdir_p!(user_dir)
    File.write!(Path.join(user_dir, filename), <<137, 80, 78, 71>>)

    conn = get(conn, ~p"/assets/#{user.id}/#{filename}")

    assert conn.status == 200
    assert hd(get_resp_header(conn, "content-type")) =~ "image/png"
  end

  test "returns forbidden for another user's asset", %{conn: conn, tmp_dir: tmp_dir} do
    other_user = user_fixture()
    filename = "preview.png"
    other_dir = Path.join(tmp_dir, other_user.id)
    File.mkdir_p!(other_dir)
    File.write!(Path.join(other_dir, filename), <<137, 80, 78, 71>>)

    conn = get(conn, ~p"/assets/#{other_user.id}/#{filename}")

    assert conn.status == 403
  end

  test "returns not found for missing asset", %{conn: conn, user: user} do
    conn = get(conn, ~p"/assets/#{user.id}/missing.png")
    assert conn.status == 404
  end

  test "requires authentication", %{tmp_dir: tmp_dir} do
    user = user_fixture()
    filename = "preview.png"
    user_dir = Path.join(tmp_dir, user.id)
    File.mkdir_p!(user_dir)
    File.write!(Path.join(user_dir, filename), <<137, 80, 78, 71>>)

    conn = build_conn() |> get(~p"/assets/#{user.id}/#{filename}")

    assert redirected_to(conn) in [~p"/users/log-in", ~p"/users/register"]
  end
end
