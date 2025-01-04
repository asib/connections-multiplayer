defmodule ConnectionsMultiplayerWeb.Game do
  use GenServer

  alias Phoenix.PubSub

  @enforce_keys [:puzzle_date, :found_categories, :cards, :category_difficulties, :hinted?]
  defstruct [:puzzle_date, :found_categories, :cards, :category_difficulties, :hinted?]

  def start_link() do
    GenServer.start_link(__MODULE__, nil)
  end

  def load(pid) do
    GenServer.call(pid, :load)
  end

  def toggle_card(pid, game_id, card, avatar, colour) do
    GenServer.call(pid, {:toggle_card, game_id, card, avatar, colour})
  end

  def deselect_all_cards(pid, game_id) do
    GenServer.call(pid, {:deselect_all, game_id})
  end

  def change_puzzle_date(pid, game_id, %Date{} = new_date) do
    GenServer.call(pid, {:change_puzzle_date, game_id, new_date})
  end

  def submit(pid, game_id) do
    GenServer.call(pid, {:submit, game_id})
  end

  def hint(pid, game_id) do
    GenServer.call(pid, {:hint, game_id})
  end

  @impl true
  def init(_) do
    case new_game() do
      {:ok, %__MODULE__{} = game} -> {:ok, game}
      _ = err -> {:stop, err}
    end
  end

  @impl true
  def handle_call(:load, _from, game_state) do
    {:reply, {:ok, game_state}, game_state}
  end

  @impl true
  def handle_call(
        {:toggle_card, game_id, card, avatar, colour},
        _from,
        %__MODULE__{cards: cards} = state
      ) do
    num_already_selected = num_cards_selected(cards)

    new_cards =
      Map.update!(cards, card, fn %{selected: selected} = card_info ->
        if num_already_selected < 4 || selected do
          if selected do
            %{card_info | selected: !selected} |> Map.drop([:avatar, :colour])
          else
            %{card_info | selected: !selected}
            |> Map.put(:avatar, avatar)
            |> Map.put(:colour, colour)
          end
        else
          card_info
        end
      end)

    new_state = %__MODULE__{state | cards: new_cards}

    PubSub.broadcast(
      ConnectionsMultiplayer.PubSub,
      "game:#{game_id}",
      {:state_update, new_state}
    )

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:deselect_all, game_id}, _from, %__MODULE__{cards: cards} = state) do
    new_cards =
      Map.new(cards, fn {card, card_info} ->
        {card, %{card_info | selected: false}}
      end)

    new_state = %__MODULE__{state | cards: new_cards}

    PubSub.broadcast(
      ConnectionsMultiplayer.PubSub,
      "game:#{game_id}",
      {:state_update, new_state}
    )

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(
        {:change_puzzle_date, game_id, %Date{} = new_date},
        _from,
        %__MODULE__{} = state
      ) do
    case new_game(new_date) do
      {:ok, %__MODULE__{} = new_game} ->
        PubSub.broadcast(
          ConnectionsMultiplayer.PubSub,
          "game:#{game_id}",
          {:state_update, new_game}
        )

        {:reply, :ok, new_game}

      _ = err ->
        {:reply, err, state}
    end
  end

  @impl true
  def handle_call(
        {:submit, game_id},
        _from,
        %__MODULE__{cards: cards, found_categories: found_categories} = game_state
      ) do
    selected_cards =
      cards |> Map.filter(fn {_card, %{selected: selected}} -> selected end)

    remaining_cards =
      cards |> Map.reject(fn {_card, %{selected: selected}} -> selected end)

    selected_categories =
      Enum.map(selected_cards, fn {_, %{category: category}} -> category end)
      |> Enum.frequencies()

    {{flash_kind, message}, new_cards, new_found_categories} =
      if map_size(selected_categories) == 1 do
        new_found_categories =
          [
            {selected_categories |> Map.keys() |> hd(),
             Enum.map(selected_cards, fn {card, _} -> card end)}
            | found_categories
          ]

        {{:success, "Woohoo"}, remaining_cards, new_found_categories}
      else
        new_cards =
          Map.new(cards, fn {card, card_info} ->
            {card, %{card_info | selected: false}}
          end)

        message =
          if map_size(selected_categories) == 2 &&
               selected_categories |> Map.values() |> Enum.any?(&(&1 == 1)) do
            "So close, just one off!"
          else
            "Bad luck, have another go."
          end

        {{:error, message}, new_cards, found_categories}
      end

    new_state =
      case flash_kind do
        :success ->
          # Reset hinted? state if a category is found
          %__MODULE__{
            game_state
            | cards: new_cards,
              found_categories: new_found_categories,
              hinted?: false
          }

        :error ->
          %__MODULE__{game_state | cards: new_cards, found_categories: new_found_categories}
      end

    PubSub.broadcast(
      ConnectionsMultiplayer.PubSub,
      "game:#{game_id}",
      {:state_update, new_state, {flash_kind, message}}
    )

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(
        {:hint, game_id},
        _from,
        %__MODULE__{
          cards: cards,
          found_categories: found_categories,
          category_difficulties: category_difficulties,
          hinted?: hinted?
        } = game_state
      ) do
    found = Enum.map(found_categories, fn {category, _} -> category end)

    [{category, _difficulty} | _rest] =
      category_difficulties
      |> Enum.filter(fn {category, _difficulty} -> !Enum.member?(found, category) end)
      |> Enum.sort_by(fn {_category, difficulty} -> difficulty end)
      |> Enum.take(1)

    num_cards = if(hinted?, do: 3, else: 2)

    hint_cards =
      cards
      |> Enum.filter(fn {_card, %{category: card_category}} -> card_category == category end)
      |> Enum.take(num_cards)
      |> Enum.map(fn {card, _card_info} -> card end)

    PubSub.broadcast(
      ConnectionsMultiplayer.PubSub,
      "game:#{game_id}",
      {:hint, hint_cards}
    )

    new_state = %__MODULE__{game_state | hinted?: true}

    {:reply, :ok, new_state}
  end

  def num_cards_selected(cards) do
    cards
    |> Map.values()
    |> Enum.count(& &1.selected)
  end

  defp new_game(puzzle_date \\ Date.utc_today()) do
    with {:ok, %{cards: cards, category_difficulties: category_difficulties}} <-
           load_cards(puzzle_date) do
      {:ok,
       %__MODULE__{
         puzzle_date: puzzle_date,
         found_categories: [],
         cards: cards,
         category_difficulties: category_difficulties,
         hinted?: false
       }}
    end
  end

  defp load_cards(%Date{year: year, month: month, day: day}) do
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
      cards =
        puzzle["categories"]
        |> Enum.flat_map(fn category ->
          Enum.map(category["cards"], fn card ->
            {card["content"],
             %{category: category["title"], position: card["position"], selected: false}}
          end)
        end)
        |> Map.new()

      difficulties =
        puzzle["categories"]
        |> Enum.map(& &1["title"])
        |> Enum.with_index()
        |> Map.new()

      {:ok,
       %{
         cards: cards,
         category_difficulties: difficulties
       }}
    end
  end
end
