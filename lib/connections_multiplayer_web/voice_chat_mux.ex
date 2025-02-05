defmodule ConnectionsMultiplayerWeb.VoiceChatMux do
  use GenServer

  alias Phoenix.PubSub

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def add_publisher_to_game(game_id, publisher_pid, publisher_id) do
    GenServer.call(__MODULE__, {:add_publisher_to_game, game_id, publisher_pid, publisher_id})
  end

  def get_publishers_for_game(game_id) do
    GenServer.call(__MODULE__, {:get_publishers_for_game, game_id})
  end

  def broadcast_packet(game_id, from_pid, from_publisher_id, packet) do
    broadcast(
      game_id,
      {:packet, %{publisher_pid: from_pid, publisher_id: from_publisher_id, packet: packet}}
    )
  end

  def subscribe(game_id) do
    PubSub.subscribe(ConnectionsMultiplayer.PubSub, topic(game_id))
  end

  def init(_) do
    {:ok, %{publishers: %{}, peers: %{}}}
  end

  def handle_call({:add_publisher_to_game, game_id, publisher_pid, publisher_id}, _from, state) do
    Process.monitor(publisher_pid)
    broadcast(game_id, {:publisher_added, publisher_pid, publisher_id})

    new_state =
      %{
        update_in(
          state,
          [:publishers, Access.key(game_id, MapSet.new())],
          &MapSet.put(&1, publisher_pid)
        )
        | peers: Map.put(state.peers, publisher_pid, %{game_id: game_id, type: :publishers})
      }

    dbg({self(), state, new_state})

    {:reply, :ok, new_state}
  end

  def handle_call({:get_publishers_for_game, game_id}, _from, state) do
    publishers_for_game_id =
      get_in(state.publishers, [Access.key(game_id, MapSet.new())])

    {:reply, {:ok, publishers_for_game_id}, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    %{game_id: game_id, type: :publishers} = Map.get(state.peers, pid)

    new_state =
      update_in(state, [:publishers, Access.key(game_id, MapSet.new())], &MapSet.delete(&1, pid))
      |> then(fn state -> update_in(state.peers, &Map.delete(&1, pid)) end)

    dbg({self(), state, new_state})

    broadcast(game_id, {:publisher_removed, pid})

    {:noreply, new_state}
  end

  defp broadcast(game_id, message) do
    PubSub.broadcast(ConnectionsMultiplayer.PubSub, topic(game_id), message)
  end

  defp topic(game_id), do: "voice_chat:#{game_id}"
end
