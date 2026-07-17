defmodule LiminalWeb.LinkLive.Shortcuts do
  use LiminalWeb, :html

  alias LiminalWeb.LinkLive.TagHandlers

  def set_platform(socket, params) do
    socket
    |> assign(:shortcut_platform, parse_shortcut_platform(params["platform"]))
    |> assign(:show_keyboard_shortcut_hints, show_keyboard_shortcut_hints?(params))
    |> assign(:show_clipboard_paste_button, show_clipboard_paste_button?(params))
    |> assign(:clipboard_has_link, false)
  end

  def set_clipboard_has_link(socket, params) do
    assign(socket, :clipboard_has_link, clipboard_has_link?(params))
  end

  def toggle_tag_by_index(socket, index) do
    case index_to_tag(index, socket.assigns.tags) do
      nil -> socket
      tag -> TagHandlers.toggle_selected_tag(socket, tag.id)
    end
  end

  def handle_keydown(
        socket,
        %{
          "key" => key,
          "code" => code,
          "shiftKey" => true,
          "altKey" => false,
          "repeat" => false
        } = params
      ) do
    with true <- mod_key_active?(params),
         {:ok, index} <- parse_digit_shortcut(key, code),
         tag when not is_nil(tag) <- Enum.at(socket.assigns.tags, index - 1) do
      {:noreply, TagHandlers.toggle_selected_tag(socket, tag.id)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_keydown(socket, _params), do: {:noreply, socket}

  def parse_shortcut_platform("mac"), do: :mac
  def parse_shortcut_platform("windows"), do: :windows
  def parse_shortcut_platform("linux"), do: :linux
  def parse_shortcut_platform(_platform), do: :linux

  def show_keyboard_shortcut_hints?(%{"show_keyboard_shortcut_hints" => false}), do: false
  def show_keyboard_shortcut_hints?(%{"show_keyboard_shortcut_hints" => "false"}), do: false
  def show_keyboard_shortcut_hints?(_params), do: true

  def show_clipboard_paste_button?(%{"show_clipboard_paste_button" => false}), do: false
  def show_clipboard_paste_button?(%{"show_clipboard_paste_button" => "false"}), do: false
  def show_clipboard_paste_button?(_params), do: true

  def clipboard_has_link?(%{"has_link" => true}), do: true
  def clipboard_has_link?(%{"has_link" => "true"}), do: true
  def clipboard_has_link?(_params), do: false

  def shortcut_mod_label(:mac), do: <<0x2318::utf8>>
  def shortcut_mod_label(:linux), do: "Super"
  def shortcut_mod_label(:windows), do: "Ctrl"

  def shortcut_mod_aria(:mac), do: "Meta"
  def shortcut_mod_aria(:linux), do: "Meta"
  def shortcut_mod_aria(:windows), do: "Control"

  def focus_url_aria_keyshortcuts(platform) do
    mod = shortcut_mod_aria(platform)
    "J #{mod}+V"
  end

  def paste_aria_keyshortcuts(platform), do: "#{shortcut_mod_aria(platform)}+V"

  def focus_search_aria_keyshortcuts, do: "F"

  def random_aria_keyshortcuts, do: "R"

  def tag_toggle_aria_keyshortcuts(index), do: "Control+Shift+#{index}"

  def tag_toggle_ctrl_label(:mac), do: <<0x2303::utf8>>
  def tag_toggle_ctrl_label(_platform), do: "Ctrl"

  def tag_toggle_shift_label(:mac), do: <<0x21E7::utf8>>
  def tag_toggle_shift_label(_platform), do: "Shift"

  def save_note_aria_keyshortcuts(platform), do: "#{save_note_mod_aria(platform)}+Enter"

  def save_note_mod_aria(:mac), do: "Meta"
  def save_note_mod_aria(:linux), do: "Control"
  def save_note_mod_aria(:windows), do: "Control"

  defp mod_key_active?(params), do: params["ctrlKey"] == true

  defp parse_digit_shortcut(_key, <<"Digit", digit::binary-size(1)>>)
       when digit in ["1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    {:ok, String.to_integer(digit)}
  end

  defp parse_digit_shortcut(_key, <<"Numpad", digit::binary-size(1)>>)
       when digit in ["1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    {:ok, String.to_integer(digit)}
  end

  defp parse_digit_shortcut(key, _code) when is_binary(key) do
    case Integer.parse(key) do
      {digit, ""} when digit >= 1 and digit <= 9 -> {:ok, digit}
      _ -> :error
    end
  end

  defp parse_digit_shortcut(_key, _code), do: :error

  defp index_to_tag(index, tags) when is_integer(index), do: Enum.at(tags, index - 1)

  defp index_to_tag(index, tags) when is_binary(index) do
    case Integer.parse(index) do
      {value, ""} -> index_to_tag(value, tags)
      _ -> nil
    end
  end

  defp index_to_tag(_index, _tags), do: nil
end
