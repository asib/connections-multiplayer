defmodule ConnectionsMultiplayerWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.

  See the [`Phoenix.Presence`](https://hexdocs.pm/phoenix/Phoenix.Presence.html)
  docs for more details.
  """
  use Phoenix.Presence,
    otp_app: :connections_multiplayer,
    pubsub_server: ConnectionsMultiplayer.PubSub

  def init(_opts) do
    {:ok, %{}}
  end

  def fetch(_topic, presences) do
    for {key, %{metas: [meta | metas]}} <- presences, into: %{} do
      {key, %{metas: [meta | metas], id: meta.id}}
    end
  end

  def handle_metas(topic, %{joins: joins, leaves: leaves}, presences, state) do
    for {user_id, _presence} <- joins do
      user_data = %{id: user_id, metas: Map.fetch!(presences, user_id)}
      msg = {__MODULE__, {:join, user_data}}

      Phoenix.PubSub.local_broadcast(
        ConnectionsMultiplayer.PubSub,
        "game_room_channel_proxy:#{topic}",
        msg
      )
    end

    for {user_id, _presence} <- leaves do
      metas =
        case Map.fetch(presences, user_id) do
          {:ok, presence_metas} -> presence_metas
          :error -> []
        end

      user_data = %{id: user_id, metas: metas}
      msg = {__MODULE__, {:leave, user_data}}

      Phoenix.PubSub.local_broadcast(
        ConnectionsMultiplayer.PubSub,
        "game_room_channel_proxy:#{topic}",
        msg
      )
    end

    {:ok, state}
  end

  def list_online_users(),
    do: list("online_users") |> Enum.map(fn {_id, presence} -> presence end)

  def track_user(name, params), do: track(self(), "online_users", name, params)

  def subscribe(),
    do:
      Phoenix.PubSub.subscribe(
        ConnectionsMultiplayer.PubSub,
        "game_room_channel_proxy:online_users"
      )
end
