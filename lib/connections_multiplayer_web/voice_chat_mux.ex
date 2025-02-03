defmodule ConnectionsMultiplayerWeb.VoiceChatMux do
  use GenServer

  alias Phoenix.PubSub

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def add_publisher_to_game(game_id, publisher_pid) do
    GenServer.call(__MODULE__, {:add_publisher_to_game, game_id, publisher_pid})
  end

  def add_listener_to_game_and_subscribe(game_id, listener_pid) do
    subscribe(game_id)
    GenServer.call(__MODULE__, {:add_listener_to_game, game_id, listener_pid})
  end

  def broadcast_packet(game_id, from_pid, packet) do
    broadcast(game_id, {:packet, from_pid, packet})
  end

  def subscribe(game_id) do
    PubSub.subscribe(ConnectionsMultiplayer.PubSub, topic(game_id))
  end

  def init(_) do
    {:ok, %{publishers: %{}, listeners: %{}, peers: %{}}}
  end

  def handle_call({:add_publisher_to_game, game_id, publisher_pid}, _from, state) do
    Process.monitor(publisher_pid)
    broadcast(game_id, {:publisher_added, publisher_pid})

    {:reply, :ok,
     %{
       update_in(
         state,
         [:publishers, Access.key(game_id, MapSet.new())],
         &MapSet.put(&1, publisher_pid)
       )
       | peers: Map.put(state.peers, publisher_pid, %{game_id: game_id, type: :publishers})
     }}
  end

  def handle_call({:add_listener_to_game, game_id, listener_pid}, _from, state) do
    Process.monitor(listener_pid)
    broadcast(game_id, {:listener_added, listener_pid})

    {:reply, {:ok, get_in(state.publishers, [Access.key(game_id, MapSet.new())])},
     %{
       update_in(
         state,
         [:listeners, Access.key(game_id, MapSet.new())],
         &MapSet.put(&1, listener_pid)
       )
       | peers: Map.put(state.peers, listener_pid, %{game_id: game_id, type: :listeners})
     }}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    %{game_id: game_id, type: type} = Map.get(state.peers, pid)

    new_state =
      update_in(state, [type, game_id], &MapSet.delete(&1, pid))
      |> then(fn state -> update_in(state.peers, &Map.delete(&1, pid)) end)

    event =
      case type do
        :publishers -> :publisher_removed
        :listeners -> :listener_removed
      end

    broadcast(game_id, {event, pid})

    {:noreply, new_state}
  end

  defp broadcast(game_id, message) do
    PubSub.broadcast(ConnectionsMultiplayer.PubSub, topic(game_id), message)
  end

  defp topic(game_id), do: "voice_chat:#{game_id}"
end
