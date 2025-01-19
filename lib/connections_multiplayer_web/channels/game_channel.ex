defmodule ConnectionsMultiplayerWeb.GameChannel do
  use ConnectionsMultiplayerWeb, :channel

  alias ConnectionsMultiplayerWeb.Presence

  @impl true
  def join("game:" <> _game_id, _params, socket) do
    send(self(), :after_join)
    {:ok, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _} =
      Presence.track(
        socket,
        socket.assigns.avatar,
        %{
          id: socket.assigns.avatar,
          colour: socket.assigns.colour
        }
      )

    {:noreply, socket}
  end
end
