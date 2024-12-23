defmodule ConnectionsMultiplayerWeb.GameRoomChannel do
  use ConnectionsMultiplayerWeb, :channel

  @impl true
  def join("game_room:lobby", payload, socket) do
    if authorized?(payload) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Add authorization logic here as required.
  defp authorized?(_payload) do
    true
  end
end
