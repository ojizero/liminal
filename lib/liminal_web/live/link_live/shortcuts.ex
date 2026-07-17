defmodule LiminalWeb.LinkLive.Shortcuts do
  import Phoenix.Component, only: [assign: 3, to_form: 1]

  alias Liminal.Links
  alias Phoenix.LiveView

  def set_shortcut_platform(socket, params) do
    socket
    |> assign(:shortcut_platform, parse_shortcut_platform(params["platform"]))
    |> assign(:show_keyboard_shortcut_hints, show_keyboard_shortcut_hints?(params))
    |> assign(:show_clipboard_paste_button, show_clipboard_paste_button?(params))
    |> assign(:clipboard_has_link, false)
  end

  def set_clipboard_has_link(socket, params) do
    assign(socket, :clipboard_has_link, clipboard_has_link?(params))
  end

  def shortcut_focus_new_link(socket) do
    socket
    |> apply_default_tags()
    |> LiveView.push_event("focus-new-link-url", %{scroll: true})
  end

  def focus_new_link(socket), do: apply_default_tags(socket)

  def shortcut_paste_link(socket, url) do
    changeset =
      socket.assigns.link
      |> Links.change_link(%{"url" => url})
      |> Map.put(:action, :validate)

    socket
    |> assign(:form, to_form(changeset))
    |> apply_default_tags()
    |> LiveView.push_event("focus-new-link-url", %{scroll: true})
  end

  def handle_shortcut_keydown(
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
      {:noreply, toggle_selected_tag(socket, tag.id)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_shortcut_keydown(socket, _params), do: {:noreply, socket}

  def shortcut_mod_label(:mac), do: "⌘"
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

  def index_to_tag(index, tags) when is_integer(index), do: Enum.at(tags, index - 1)

  def index_to_tag(index, tags) when is_binary(index) do
    case Integer.parse(index) do
      {value, ""} -> index_to_tag(value, tags)
      _ -> nil
    end
  end

  def index_to_tag(_index, _tags), do: nil

  def apply_default_tags(socket) do
    user = socket.assigns.current_scope.user

    with true <- user.default_tags_enabled,
         tag_id when not is_nil(tag_id) <- user.default_tag_id,
         tag_id <- normalize_tag_id(tag_id),
         true <- Enum.any?(socket.assigns.tags, &(normalize_tag_id(&1.id) == tag_id)) do
      assign(socket, :selected_tag_ids, [tag_id])
    else
      _ -> socket
    end
  end

  def normalize_tag_id(id), do: to_string(id)

  def toggle_selected_tag(socket, tag_id) do
    tag_id = normalize_tag_id(tag_id)
    selected = Enum.map(socket.assigns.selected_tag_ids, &normalize_tag_id/1)

    updated =
      case tag_id in selected do
        true -> List.delete(selected, tag_id)
        false -> [tag_id | selected]
      end

    assign(socket, :selected_tag_ids, updated)
  end

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

  def mod_key_active?(params), do: params["ctrlKey"] == true

  def parse_digit_shortcut(_key, <<"Digit", digit::binary-size(1)>>)
      when digit in ["1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    {:ok, String.to_integer(digit)}
  end

  def parse_digit_shortcut(_key, <<"Numpad", digit::binary-size(1)>>)
      when digit in ["1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    {:ok, String.to_integer(digit)}
  end

  def parse_digit_shortcut(key, _code) when is_binary(key) do
    case Integer.parse(key) do
      {digit, ""} when digit >= 1 and digit <= 9 -> {:ok, digit}
      _ -> :error
    end
  end

  def parse_digit_shortcut(_key, _code), do: :error
end
