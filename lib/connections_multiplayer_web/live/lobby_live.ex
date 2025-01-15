defmodule ConnectionsMultiplayerWeb.LobbyLive do
  use ConnectionsMultiplayerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"<button>New Game</button>"
  end
end
