defmodule Liminal.AssetPaths do
  @moduledoc false

  @default_relative "assets"

  def assets_dir do
    Application.get_env(:liminal, :assets_dir, default_assets_dir())
  end

  def ensure_assets_dir! do
    File.mkdir_p!(assets_dir())
  end

  def file_path(image_path) when is_binary(image_path) do
    Path.join(assets_dir(), Path.basename(image_path))
  end

  def relative_path(filename) when is_binary(filename) do
    Path.join(@default_relative, filename)
  end

  defp default_assets_dir do
    Path.expand("data.local/assets", File.cwd!())
  end
end
