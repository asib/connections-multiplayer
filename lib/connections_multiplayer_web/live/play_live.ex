defmodule ConnectionsMultiplayerWeb.PlayLive do
  alias ConnectionsMultiplayerWeb.Game
  use ConnectionsMultiplayerWeb, :live_view

  alias Phoenix.LiveView.AsyncResult

  @game_id "hardcoded-game-id"

  @impl true
  def mount(_params, _session, socket) do
    puzzle_date = Date.utc_today()

    if connected?(socket) do
      Game.subscribe(@game_id)
    end

    socket = load_new_game(socket, puzzle_date)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_card", %{"card" => card}, socket) do
    Game.toggle_card(@game_id, card, !socket.assigns.cards.result[card].selected)

    {:noreply, socket}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    Game.deselect_all(@game_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_puzzle_date", %{"date" => new_date}, socket) do
    Game.change_puzzle_date(@game_id, Date.from_iso8601!(new_date))

    {:noreply, socket}
  end

  @impl true
  def handle_event("submit", _params, socket) do
    Game.submit(@game_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:toggle_card, card, is_selected}, socket) do
    num_already_selected = num_cards_selected(socket.assigns.cards.result)

    socket =
      update(socket, :cards, fn cards ->
        new_cards =
          Map.update!(cards.result, card, fn card_info ->
            if num_already_selected < 4 || !is_selected do
              %{card_info | selected: is_selected}
            else
              card_info
            end
          end)

        AsyncResult.ok(cards, new_cards)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:deselect_all, socket) do
    socket =
      update(socket, :cards, fn cards ->
        new_cards =
          Map.new(cards.result, fn {card, card_info} ->
            {card, %{card_info | selected: false}}
          end)

        AsyncResult.ok(cards, new_cards)
      end)

    {:noreply, socket}
  end

  def handle_info({:change_puzzle_date, new_date}, socket) do
    socket = load_new_game(socket, new_date)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:submit, socket) do
    selected_cards =
      socket.assigns.cards.result |> Map.filter(fn {_card, %{selected: selected}} -> selected end)

    remaining_cards =
      socket.assigns.cards.result |> Map.reject(fn {_card, %{selected: selected}} -> selected end)

    selected_categories =
      Enum.map(selected_cards, fn {_, %{category: category}} -> category end)
      |> Enum.frequencies()

    {socket, new_cards, new_found_categories} =
      if map_size(selected_categories) == 1 do
        new_found_categories =
          Map.put(
            socket.assigns.found_categories,
            selected_categories |> Map.keys() |> hd(),
            Enum.map(selected_cards, fn {card, _} -> card end)
          )

        {put_flash(socket, :success, "Woohoo"), remaining_cards, new_found_categories}
      else
        Game.deselect_all(@game_id)

        message =
          if map_size(selected_categories) == 2 &&
               selected_categories |> Map.values() |> Enum.any?(&(&1 == 1)) do
            "So close, just one off!"
          else
            "Bad luck, have another go."
          end

        {put_flash(socket, :error, message), socket.assigns.cards.result,
         socket.assigns.found_categories}
      end

    socket =
      socket
      |> update(:cards, fn cards -> AsyncResult.ok(cards, new_cards) end)
      |> assign(:found_categories, new_found_categories)

    {:noreply, socket}
  end

  defp load_new_game(socket, puzzle_date) do
    socket
    |> assign(:puzzle_date, puzzle_date)
    |> assign(:puzzle_date_form, to_form(%{"date" => puzzle_date}))
    |> assign(:found_categories, %{})
    |> assign_async(:cards, fn -> async_load_cards(puzzle_date) end)
  end

  defp async_load_cards(%Date{year: year, month: month, day: day}) do
    month = String.pad_leading("#{month}", 2, "0")
    day = String.pad_leading("#{day}", 2, "0")

    # {
    #   "status": "OK",
    #   "id": 190,
    #   "print_date": "2023-12-18",
    #   "editor": "Wyna Liu",
    #   "categories": [
    #     {
    #       "title": "BRIEF MOMENT",
    #       "cards": [
    #         {
    #           "content": "FLASH",
    #           "position": 10
    #         },
    #         ...
    #       ]
    #     },
    #     ...
    #   ]
    # }

    with {:query_puzzle_data, {:ok, %Req.Response{status: 200, body: puzzle}}} <-
           {:query_puzzle_data,
            Req.get("https://www.nytimes.com/svc/connections/v2/#{year}-#{month}-#{day}.json")} do
      {:ok,
       %{
         cards:
           puzzle["categories"]
           |> Enum.flat_map(fn category ->
             Enum.map(category["cards"], fn card ->
               {card["content"],
                %{category: category["title"], position: card["position"], selected: false}}
             end)
           end)
           |> Map.new()
       }}
    end
  end

  defp cards_in_order(cards) do
    cards
    |> Map.to_list()
    |> Enum.sort_by(fn {_, %{position: position}} -> position end)
    |> Enum.map(fn {content, %{selected: selected}} -> {content, selected} end)
  end

  defp num_cards_selected(cards) do
    cards
    |> Map.values()
    |> Enum.count(& &1.selected)
  end

  defp human_month(%Date{month: month}) do
    case month do
      1 -> "January"
      2 -> "February"
      3 -> "March"
      4 -> "April"
      5 -> "May"
      6 -> "June"
      7 -> "July"
      8 -> "August"
      9 -> "September"
      10 -> "October"
      11 -> "November"
      12 -> "December"
    end
  end

  defp submittable(cards) do
    cards.ok? && num_cards_selected(cards.result) == 4
  end
end
