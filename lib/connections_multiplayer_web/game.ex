defmodule ConnectionsMultiplayerWeb.Game do
  alias Phoenix.PubSub

  def subscribe(game_id) do
    PubSub.subscribe(ConnectionsMultiplayer.PubSub, "game:#{game_id}")
  end

  def toggle_card(game_id, card) do
    PubSub.broadcast(ConnectionsMultiplayer.PubSub, "game:#{game_id}", {:toggle_card, card})
  end

  def deselect_all(game_id) do
    PubSub.broadcast(ConnectionsMultiplayer.PubSub, "game:#{game_id}", :deselect_all)
  end

  def submit(game_id) do
    PubSub.broadcast(ConnectionsMultiplayer.PubSub, "game:#{game_id}", :submit)
  end
end
