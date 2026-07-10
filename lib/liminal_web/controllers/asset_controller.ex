defmodule LiminalWeb.AssetController do
  use LiminalWeb, :controller

  alias Liminal.AssetPaths

  def show(conn, %{"user_id" => user_id, "filename" => filename}) do
    current_user = conn.assigns.current_scope.user

    with :ok <- authorize_user(current_user.id, user_id),
         :ok <- validate_filename(filename),
         :ok <- validate_user_id(user_id),
         image_path when is_binary(image_path) <- build_image_path(user_id, filename),
         full_path when is_binary(full_path) <- safe_file_path(image_path),
         true <- File.regular?(full_path) do
      content_type = MIME.from_path(filename)

      conn
      |> put_resp_content_type(content_type)
      |> send_file(200, full_path)
    else
      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> text("Forbidden")

      _ ->
        conn |> put_status(:not_found) |> text("Not found")
    end
  end

  defp authorize_user(current_user_id, user_id) do
    if to_string(current_user_id) == user_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp validate_filename(filename) do
    if AssetPaths.valid_filename?(filename) do
      :ok
    else
      {:error, :not_found}
    end
  end

  defp validate_user_id(user_id) do
    if AssetPaths.valid_user_id?(user_id) do
      :ok
    else
      {:error, :not_found}
    end
  end

  defp build_image_path(user_id, filename) do
    AssetPaths.relative_path(user_id, filename)
  end

  defp safe_file_path(image_path) do
    case AssetPaths.parse_relative_path(image_path) do
      {:ok, _user_id, _filename} -> AssetPaths.file_path(image_path)
      _ -> {:error, :not_found}
    end
  end
end
