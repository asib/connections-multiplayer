defmodule ConnectionsMultiplayerWeb.PlayLive do
  use ConnectionsMultiplayerWeb, :live_view

  alias ConnectionsMultiplayerWeb.Game
  alias ConnectionsMultiplayerWeb.GameRegistry
  alias Phoenix.LiveView.AsyncResult

  @game_id "hardcoded-game-id"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      GameRegistry.subscribe(@game_id)
    end

    socket =
      assign_async(
        socket,
        [:puzzle_date, :puzzle_date_form, :found_categories, :cards, :category_difficulties],
        fn -> load_game(@game_id) end
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_card", %{"card" => card}, socket) do
    :ok = GameRegistry.toggle_card(@game_id, card)

    {:noreply, socket}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    :ok = GameRegistry.deselect_all_cards(@game_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_puzzle_date", %{"date" => new_date}, socket) do
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
        GameRegistry.change_puzzle_date(@game_id, Date.from_iso8601!(new_date))
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("submit", _params, socket) do
    :ok = GameRegistry.submit(@game_id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:state_update, new_state}, socket) do
    socket =
      new_state
      |> game_state_to_map()
      |> then(&assign_game_state(socket, &1))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:state_update, new_state, {flash_kind, message}}, socket) do
    socket =
      new_state
      |> game_state_to_map()
      |> then(&assign_game_state(socket, &1))
      |> put_flash(flash_kind, message)

    {:noreply, socket}
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

  defp cards_in_order(cards) do
    cards
    |> Map.to_list()
    |> Enum.sort_by(fn {_, %{position: position}} -> position end)
    |> Enum.map(fn {content, %{selected: selected}} -> {content, selected} end)
  end

  defp category_colour(difficulty) do
    case difficulty do
      0 -> "bg-[#f9df6d]"
      1 -> "bg-[#a0c35a]"
      2 -> "bg-[#b0c4ef]"
      3 -> "bg-[#ba81c5]"
    end
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
    cards.ok? && Game.num_cards_selected(cards.result) == 4
  end
end
