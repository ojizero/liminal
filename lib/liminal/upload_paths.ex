defmodule Liminal.UploadPaths do
  @moduledoc false

  @default_relative "uploads/images"

  def upload_dir do
    Application.get_env(:liminal, :upload_dir, default_upload_dir())
  end

  def upload_static_from do
    Application.get_env(:liminal, :upload_static_from, Path.dirname(default_upload_dir()))
  end

  def ensure_upload_dir! do
    File.mkdir_p!(upload_dir())
  end

  def file_path(image_path) when is_binary(image_path) do
    Path.join(upload_dir(), Path.basename(image_path))
  end

  def relative_path(filename) when is_binary(filename) do
    Path.join(@default_relative, filename)
  end

  defp default_upload_dir do
    Path.join(Application.app_dir(:liminal, "priv/static"), @default_relative)
  end
end
