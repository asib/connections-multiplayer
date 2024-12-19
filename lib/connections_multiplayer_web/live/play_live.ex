defmodule ConnectionsMultiplayerWeb.PlayLive do
  use ConnectionsMultiplayerWeb, :live_view

  alias Phoenix.LiveView.AsyncResult

  def mount(_params, _session, socket) do
    puzzle_date = Date.utc_today()

    socket =
      socket
      |> assign(:puzzle_date, puzzle_date)
      |> assign_async(:cards, fn -> async_load_cards(puzzle_date) end)

    {:ok, socket}
  end

  def handle_event("toggle_card", %{"card" => card}, socket) do
    num_already_selected =
      socket.assigns.cards.result |> Map.values() |> Enum.count(& &1.selected)

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

  def render(assigns) do
    ~H"""
    <.async_result :let={cards} assign={@cards}>
      <:loading>Fetching cards...</:loading>
      <:failed>Failed to fetch cards, retry...</:failed>
      <div class="grid grid-cols-4 gap-x-3 gap-y-2">
        <div
          :for={{card, selected} <- cards_in_order(cards)}
          phx-click="toggle_card"
          phx-value-card={card}
          class={[
            "text-center py-8 rounded-md",
            if(selected, do: "bg-gray-400", else: "bg-gray-200")
          ]}
        >
          {card}
        </div>
      </div>
    </.async_result>
    """
  end
end
