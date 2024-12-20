defmodule ConnectionsMultiplayerWeb.Game do
  alias Phoenix.PubSub

  def subscribe(game_id) do
    PubSub.subscribe(ConnectionsMultiplayer.PubSub, "game:#{game_id}")
  end

  def toggle_card(game_id, card, is_selected) do
    PubSub.broadcast(
      ConnectionsMultiplayer.PubSub,
      "game:#{game_id}",
      {:toggle_card, card, is_selected}
    )
  end

  def deselect_all(game_id) do
    PubSub.broadcast(ConnectionsMultiplayer.PubSub, "game:#{game_id}", :deselect_all)
  end

  def change_puzzle_date(game_id, new_date) do
    PubSub.broadcast(
      ConnectionsMultiplayer.PubSub,
      "game:#{game_id}",
      {:change_puzzle_date, new_date}
    )
  end

  def submit(game_id) do
    PubSub.broadcast(ConnectionsMultiplayer.PubSub, "game:#{game_id}", :submit)
  end
end
