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

    socket =
      socket
      |> assign(:puzzle_date, puzzle_date)
      |> assign(:found_categories, %{})
      |> assign_async(:cards, fn -> async_load_cards(puzzle_date) end)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_card", %{"card" => card}, socket) do
    Game.toggle_card(@game_id, card)

    {:noreply, socket}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    Game.deselect_all(@game_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("submit", _params, socket) do
    Game.submit(@game_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:toggle_card, card}, socket) do
    num_already_selected = num_cards_selected(socket.assigns.cards.result)

    socket =
      update(socket, :cards, fn cards ->
        new_cards =
          Map.update!(cards.result, card, fn %{selected: selected} = card_info ->
            if num_already_selected < 4 || selected do
              %{card_info | selected: !selected}
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

  def cards_in_order(cards) do
    cards
    |> Map.to_list()
    |> Enum.sort_by(fn {_, %{position: position}} -> position end)
    |> Enum.map(fn {content, %{selected: selected}} -> {content, selected} end)
  end

  def num_cards_selected(cards) do
    cards
    |> Map.values()
    |> Enum.count(& &1.selected)
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        month:
          case assigns.puzzle_date.month do
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
          end,
        submittable: assigns.cards.ok? && num_cards_selected(assigns.cards.result) == 4
      )

    ~H"""
    <p class="font-light font-serif pb-4">{@month} {@puzzle_date.day}, {@puzzle_date.year}</p>
    <div class="grid grid-cols-4 gap-x-3 gap-y-2">
      <.async_result :let={cards} assign={@cards}>
        <:loading>
          <button
            :for={_ <- 1..16}
            class="text-center py-6 rounded-md font-bold text-lg bg-card flex justify-center items-center"
          >
            &nbsp;
          </button>
        </:loading>
        <:failed>Failed to fetch cards, retry...</:failed>
        <button
          :for={{card, selected} <- cards_in_order(cards)}
          phx-click="toggle_card"
          phx-value-card={card}
          class={[
            "text-center py-6 rounded-md font-bold text-lg",
            if(selected, do: "bg-card-selected", else: "bg-card"),
            selected && "text-white"
          ]}
        >
          {card}
        </button>
      </.async_result>
    </div>
    <div class="w-full pt-4 flex justify-center space-x-2">
      <button
        class={[
          "border border-gray-800 rounded-full py-4 px-6 text-center",
          !@submittable && "!border-gray-300 text-gray-300"
        ]}
        disabled={!@submittable}
        phx-click="submit"
      >
        Submit
      </button>
      <button
        class="border border-gray-800 rounded-full py-4 px-6 text-center"
        phx-click="deselect_all"
      >
        Deselect All
      </button>
    </div>
    """
  end
end
