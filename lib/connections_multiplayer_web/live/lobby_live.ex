defmodule ConnectionsMultiplayerWeb.LobbyLive do
  use ConnectionsMultiplayerWeb, :live_view

  alias ConnectionsMultiplayerWeb.GameRegistry

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      GameRegistry.subscribe_registry_updates()
    end

    socket =
      socket
      |> assign(:active_games_count, GameRegistry.active_games_count())
      |> assign(:active_players_count, GameRegistry.active_players_count())

    {:ok, socket}
  end

  @impl true
  def handle_info(
        {ConnectionsMultiplayerWeb.GameRegistry, {:new_active_games_count, active_games_count}},
        socket
      ) do
    {:noreply, assign(socket, :active_games_count, active_games_count)}
  end

  @impl true
  def handle_info(
        {ConnectionsMultiplayerWeb.GameRegistry,
         {:new_active_players_count, active_players_count}},
        socket
      ) do
    {:noreply, assign(socket, :active_players_count, active_players_count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-rows-[1fr,min-content,1fr] h-full rounded-lg mx-auto bg-[rgb(179,167,254)] p-4">
      <h1 class="text-3xl font-[Charter] text-center pb-8 self-end">
        Connections Multiplayer
      </h1>

      <div class="flex flex-col justift-center items-center">
        <button
          class="bg-black text-white rounded-full py-2 px-4 sm:py-4 sm:px-6 text-center"
          phx-click="new-game"
        >
          New Game
        </button>
        <p class="pt-4">
          {@active_games_count} games are currently being played with {@active_players_count} players online.
        </p>
      </div>
    </div>
    """
  end
end
