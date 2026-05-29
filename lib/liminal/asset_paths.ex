defmodule Liminal.AssetPaths do
  @moduledoc false

  @default_relative "assets"

  def assets_dir do
    Application.get_env(:liminal, :assets_dir, default_assets_dir())
  end

  def ensure_assets_dir! do
    File.mkdir_p!(assets_dir())
  end

  def ensure_user_assets_dir!(user_id) do
    File.mkdir_p!(user_assets_dir(user_id))
  end

  def user_assets_dir(user_id) do
    Path.join(assets_dir(), user_id_string(user_id))
  end

  def file_path(image_path) when is_binary(image_path) do
    case parse_relative_path(image_path) do
      {:ok, user_id, filename} ->
        Path.join([assets_dir(), user_id, filename])

      {:legacy, filename} ->
        Path.join(assets_dir(), filename)

      :error ->
        Path.join(assets_dir(), Path.basename(image_path))
    end
  end

  def relative_path(user_id, filename) when is_binary(filename) and filename != "" do
    Path.join([@default_relative, user_id_string(user_id), filename])
  end

  def owned_by_user?(image_path, user_id) do
    case parse_relative_path(image_path) do
      {:ok, path_user_id, _filename} -> path_user_id == user_id_string(user_id)
      _ -> false
    end
  end

  def parse_relative_path(image_path) when is_binary(image_path) do
    case String.split(image_path, "/", parts: 3) do
      [@default_relative, user_id, filename]
      when user_id != "" and filename != "" ->
        if valid_path_segment?(user_id) and valid_path_segment?(filename) do
          {:ok, user_id, filename}
        else
          :error
        end

      [@default_relative, filename] when filename != "" ->
        if valid_path_segment?(filename) do
          {:legacy, filename}
        else
          :error
        end

      _ ->
        :error
    end
  end

  def valid_filename?(filename) when is_binary(filename) do
    filename != "" and valid_path_segment?(filename)
  end

  def valid_user_id?(user_id) when is_binary(user_id) do
    user_id != "" and valid_path_segment?(user_id)
  end

  defp user_id_string(user_id) when is_binary(user_id), do: user_id
  defp user_id_string(user_id), do: to_string(user_id)

  defp valid_path_segment?(segment) do
    segment != ".." and not String.contains?(segment, ["/", "\\", ".."])
  end

  defp default_assets_dir do
    Path.expand("data.local/assets", File.cwd!())
  end
end
