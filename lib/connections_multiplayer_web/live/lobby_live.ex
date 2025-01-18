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
  def handle_event("new-game", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/#{random_game_id()}")}
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
    <div class="flex flex-col items-center justify-center h-full w-full">
      <div class="flex flex-col flex-wrap items-center justify-center content-center lg:grid lg:grid-rows-[1fr,min-content,1fr] h-[calc(100%-26vh)] lg:h-[calc(100%-34vh)] w-full rounded-lg bg-[rgb(179,167,254)] p-4 mx-4">
        <h1 class="text-2xl md:text-3xl font-[Charter] text-center pb-8 lg:self-end">
          Connections Multiplayer
        </h1>

        <div class="flex flex-col justify-center items-center">
          <button
            class="bg-black text-white rounded-full py-2 px-4 sm:py-4 sm:px-6 text-center"
            phx-click="new-game"
          >
            New Game
          </button>
          <p class="pt-4 text-center">
            <span class="font-bold">
              {case @active_games_count do
                {:error, :could_not_get_active_games_count} -> "0"
                count -> count
              end}
            </span>
            games are currently being played with
            <span class="font-bold">{@active_players_count}</span>
            players online.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp random_game_id() do
    MnemonicSlugs.generate_slug(3)
  end
end
