defmodule LiminalWeb.Plugs.UploadStatic do
  @moduledoc false
  @behaviour Plug

  @impl Plug
  def init(_opts) do
    Plug.Static.init(
      at: "/uploads",
      from: Liminal.UploadPaths.upload_static_from(),
      only: ~w(images),
      gzip: gzip_static?()
    )
  end

  @impl Plug
  def call(conn, opts), do: Plug.Static.call(conn, opts)

  defp gzip_static? do
    case Application.get_env(:liminal, LiminalWeb.Endpoint) do
      config when is_list(config) -> config[:cache_static_manifest] != nil
      _ -> false
    end
  end
end
