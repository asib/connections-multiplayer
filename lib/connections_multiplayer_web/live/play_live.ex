defmodule ConnectionsMultiplayerWeb.PlayLive do
  alias ConnectionsMultiplayerWeb.Presence
  use ConnectionsMultiplayerWeb, :live_view

  alias ConnectionsMultiplayerWeb.Game
  alias ConnectionsMultiplayerWeb.GameRegistry
  alias Phoenix.LiveView.AsyncResult

  @game_id "hardcoded-game-id"

  @avatars [
    "Duck",
    "Rabbit",
    "Ifrit",
    "Ibex",
    "Turtle",
    "Leopard",
    "Gopher",
    "Ferret",
    "Beaver",
    "Chinchilla",
    "Auroch",
    "Dingo",
    "Kraken",
    "Rhino",
    "Python",
    "Cormorant",
    "Platypus",
    "Elephant",
    "Jackal",
    "Dolphin",
    "Capybara",
    "Camel",
    "Chupacabra",
    "Tiger",
    "Kangaroo",
    "Armadillo",
    "Sheep",
    "Panda",
    "Hippo",
    "Cheetah",
    "Manatee",
    "Raccoon",
    "Wombat",
    "Dinosaur",
    "Hyena",
    "Crow",
    "Orangutan",
    "Wolf",
    "Chameleon",
    "Shrew",
    "Penguin",
    "Nyan Cat",
    "Liger",
    "Quagga",
    "Squirrel",
    "Wolverine",
    "Axolotl",
    "Anteater",
    "Frog",
    "Narwhal",
    "Mink",
    "Chipmunk",
    "Buffalo",
    "Monkey",
    "Bat",
    "Giraffe",
    "Iguana",
    "Fox",
    "Coyote",
    "Moose",
    "Otter",
    "Grizzly",
    "Koala",
    "Alligator",
    "Pumpkin",
    "Llama",
    "Badger",
    "Walrus",
    "Skunk",
    "Lemur",
    "Hedgehog"
  ]

  @colours ~w(
    bg-slate-600
    bg-red-900
    bg-orange-700
    bg-amber-600
    bg-lime-600
    bg-green-800
    bg-teal-600
    bg-cyan-600
    bg-sky-700
    bg-blue-600
    bg-indigo-600
    bg-violet-700
    bg-purple-600
    bg-fuchsia-700
    bg-pink-500
    bg-rose-700
  )

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      GameRegistry.subscribe(@game_id)
    end

    socket = stream(socket, :presences, [])

    socket =
      if connected?(socket) do
        socket =
          if !is_nil(socket.assigns[:avatar]) do
            socket
          else
            socket
            |> assign(:avatar, "#{Enum.random(@avatars)}-#{:rand.uniform(999_999_999_999)}")
          end

        Presence.track_user(socket.assigns.avatar, %{
          id: socket.assigns.avatar,
          colour: Enum.random(@colours)
        })

        Presence.subscribe()
        stream(socket, :presences, Presence.list_online_users())
      else
        socket
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

  defp submittable(cards) do
    cards.ok? && Game.num_cards_selected(cards.result) == 4
  end

  defp avatar_name(id) do
    [name, _] = String.split(id, "-")
    name
  end
end
