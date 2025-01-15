defmodule ConnectionsMultiplayerWeb.Hooks.InitAssigns do
  import Phoenix.Component

  def on_mount(:default, _params, _session, socket) do
    {:cont, assign(socket, :is_game_page?, false)}
  end
end
