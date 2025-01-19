defmodule ConnectionsMultiplayerWeb.PlayLive do
  use ConnectionsMultiplayerWeb, :live_view

  alias ConnectionsMultiplayerWeb.Game
  alias ConnectionsMultiplayerWeb.GameRegistry
  alias ConnectionsMultiplayerWeb.Presence
  alias Phoenix.LiveView.AsyncResult

  require Logger

  @impl true
  def mount(%{"game_id" => game_id}, _session, socket) do
    socket =
      socket
      |> stream(:presences, [])
      |> assign(:game_id, game_id)
      |> assign(:is_game_page?, true)
      |> assign_async(
        [:puzzle_date, :puzzle_date_form, :found_categories, :cards, :category_difficulties],
        fn -> load_game(game_id) end
      )

    socket =
      if connected?(socket) do
        GameRegistry.subscribe(socket.assigns.game_id)

        stream(socket, :presences, Presence.list_online_users(socket.assigns.game_id))
      else
        socket
      end

    Presence.subscribe(socket.assigns.game_id)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_card", %{"card" => card, "is_long_press" => is_long_press}, socket) do
    :ok =
      GameRegistry.toggle_card(
        socket.assigns.game_id,
        card,
        socket.assigns.avatar,
        socket.assigns.colour,
        is_long_press
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("hint", _params, socket) do
    :ok = GameRegistry.hint(socket.assigns.game_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    :ok = GameRegistry.deselect_all_cards(socket.assigns.game_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_puzzle_date", %{"date" => new_date}, socket) do
    # Create variable to avoid passing entire socket into the start_async() closure below
    game_id = socket.assigns.game_id

    socket =
      socket
      |> update(:puzzle_date, fn puzzle_date ->
        AsyncResult.loading(puzzle_date)
      end)
      |> update(:puzzle_date_form, fn puzzle_date_form ->
        AsyncResult.loading(puzzle_date_form)
      end)
      |> update(:found_categories, fn found_categories ->
        AsyncResult.loading(found_categories)
      end)
      |> update(:cards, fn cards -> AsyncResult.loading(cards) end)
      |> update(:category_difficulties, fn category_difficulties ->
        AsyncResult.loading(category_difficulties)
      end)
      |> start_async(:change_puzzle_date_task, fn ->
        GameRegistry.change_puzzle_date(game_id, Date.from_iso8601!(new_date))
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("submit", _params, socket) do
    :ok = GameRegistry.submit(socket.assigns.game_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:state_update, new_state}, socket) do
    socket =
      new_state
      |> game_state_to_map()
      |> then(&assign_game_state(socket, &1))
      |> maybe_fire_confetti(socket.assigns.found_categories.result, new_state.found_categories)
      |> push_card_updates_to_client(new_state.cards)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:state_update, new_state, {flash_kind, message}}, socket) do
    socket =
      new_state
      |> game_state_to_map()
      |> then(&assign_game_state(socket, &1))
      |> put_flash(flash_kind, message)
      |> maybe_fire_confetti(socket.assigns.found_categories.result, new_state.found_categories)
      |> push_card_updates_to_client(new_state.cards)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:hint, cards}, socket) do
    socket =
      Enum.reduce(cards, socket, fn card, socket ->
        push_event(socket, "animate-hint-#{card}", %{})
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({ConnectionsMultiplayerWeb.Presence, {:join, presence}}, socket) do
    {:noreply, stream_insert(socket, :presences, presence)}
  end

  @impl true
  def handle_info({ConnectionsMultiplayerWeb.Presence, {:leave, presence}}, socket) do
    if presence.metas == [] do
      {:noreply, stream_delete(socket, :presences, presence)}
    else
      {:noreply, stream_insert(socket, :presences, presence)}
    end
  end

  @impl true
  def handle_async(:change_puzzle_date_task, {:ok, result}, socket) do
    socket =
      case result do
        :ok -> socket
        reason -> set_async_results_to_failed(socket, reason)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_async(:change_puzzle_date_task, {:exit, _} = reason, socket) do
    socket = set_async_results_to_failed(socket, reason)

    {:noreply, socket}
  end

  defp push_card_updates_to_client(socket, cards) do
    Enum.reduce(cards, socket, fn {card, card_info}, socket ->
      push_event(socket, "update-card-#{card}", %{
        selected: card_info.selected,
        avatar: Map.get(card_info, :avatar),
        colour: Map.get(card_info, :colour)
      })
    end)
  end

  defp set_async_results_to_failed(socket, reason) do
    socket
    |> update(:puzzle_date, fn puzzle_date -> AsyncResult.failed(puzzle_date, reason) end)
    |> update(:puzzle_date_form, fn puzzle_date_form ->
      AsyncResult.failed(puzzle_date_form, reason)
    end)
    |> update(:found_categories, fn found_categories ->
      AsyncResult.failed(found_categories, reason)
    end)
    |> update(:cards, fn cards -> AsyncResult.failed(cards, reason) end)
    |> update(:category_difficulties, fn category_difficulties ->
      AsyncResult.failed(category_difficulties, reason)
    end)
    |> put_flash(:error, "Failed to change puzzle date")
  end

  defp load_game(game_id) do
    with {:ok, game_state} <- GameRegistry.load(game_id) do
      {:ok, game_state_to_map(game_state)}
    end
  end

  def game_state_to_map(%Game{
        puzzle_date: puzzle_date,
        found_categories: found_categories,
        cards: cards,
        category_difficulties: category_difficulties
      }) do
    %{
      puzzle_date: puzzle_date,
      puzzle_date_form: to_form(%{"date" => puzzle_date}),
      found_categories: found_categories,
      cards: cards,
      category_difficulties: category_difficulties
    }
  end

  def assign_game_state(socket, %{
        puzzle_date: new_puzzle_date,
        puzzle_date_form: new_puzzle_date_form,
        found_categories: new_found_categories,
        cards: new_cards,
        category_difficulties: new_category_difficulties
      }) do
    socket
    |> update(:puzzle_date, fn puzzle_date -> AsyncResult.ok(puzzle_date, new_puzzle_date) end)
    |> update(:puzzle_date_form, fn puzzle_date_form ->
      AsyncResult.ok(puzzle_date_form, new_puzzle_date_form)
    end)
    |> update(:found_categories, fn found_categories ->
      AsyncResult.ok(found_categories, new_found_categories)
    end)
    |> update(:cards, fn cards -> AsyncResult.ok(cards, new_cards) end)
    |> update(:category_difficulties, fn category_difficulties ->
      AsyncResult.ok(category_difficulties, new_category_difficulties)
    end)
  end

  defp maybe_fire_confetti(socket, old_found_categories, new_found_categories) do
    if length(old_found_categories) < length(new_found_categories) do
      push_event(socket, "fire-confetti-cannon", %{})
    else
      socket
    end
  end

  defp cards_in_order(cards) do
    cards
    |> Map.to_list()
    |> Enum.sort_by(fn {_, %{position: position}} -> position end)
    |> Enum.map(fn {content, params} ->
      {content, Map.take(params, [:selected, :avatar, :colour])}
    end)
  end

  defp category_colour(difficulty) do
    case difficulty do
      0 -> "bg-[#f9df6d]"
      1 -> "bg-[#a0c35a]"
      2 -> "bg-[#b0c4ef]"
      3 -> "bg-[#ba81c5]"
    end
  end

  defp border_colour_from_bg_colour(nil), do: nil

  defp border_colour_from_bg_colour(colour) do
    String.replace_prefix(colour, "bg-", "border-")
  end

  defp card_button_class(params) do
    [
      "rounded-md font-bold overflow-hidden",
      "flex flex-wrap content-center justify-center bg-card",
      if(params.selected,
        do: ["border-4 p-1", border_colour_from_bg_colour(params.colour)],
        else: "p-2"
      )
    ]
  end

  defp completed_category_class(category_difficulties, category) do
    [
      "flex flex-col content-center justify-center text-center col-span-4 rounded-md",
      category_colour(category_difficulties[category])
    ]
  end

  defp submittable(cards) do
    cards.ok? && Game.num_cards_selected(cards.result) == 4
  end

  defp hintable(cards) do
    !cards.ok? || is_nil(cards.result) || map_size(cards.result) > 4
  end

  defp avatar_name(nil), do: nil
  defp avatar_name(""), do: nil

  defp avatar_name(id) do
    [name, _] = String.split(id, "-")
    name
  end
end
