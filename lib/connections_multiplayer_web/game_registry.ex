defmodule ConnectionsMultiplayerWeb.GameRegistry do
  use GenServer

  alias Phoenix.PubSub
  alias ConnectionsMultiplayerWeb.Game
  alias ConnectionsMultiplayerWeb.GameRegistry.Game, as: GameTable
  alias ConnectionsMultiplayerWeb.Presence

  @registry_pubsub_topic "game_registry:updates"

  @impl true
  def init(_) do
    Memento.Table.create(GameTable)

    case calculate_active_players() do
      {:ok, active_players} ->
        {:ok, %{active_players: active_players}}

      {:error, :could_not_calculate_active_players} ->
        {:stop, {:error, :could_not_calculate_active_players}}
    end
  end

  @impl true
  def handle_call({:load, game_id}, _from, state) do
    with {:ok, %GameTable{id: ^game_id, pid: game_pid}} <- lookup(game_id),
         {:ok, game_state} <- Game.load(game_pid) do
      {:reply, {:ok, game_state}, state}
    else
      _ ->
        Presence.subscribe(game_id)
        {:ok, new_game} = create_new_game(game_id)

        with {:ok, rows} <- all_rows() do
          PubSub.broadcast(
            ConnectionsMultiplayer.PubSub,
            @registry_pubsub_topic,
            {__MODULE__, {:new_active_games_count, length(rows)}}
          )
        end

        {:reply, {:ok, new_game}, state}
    end
  end

  @impl true
  def handle_call({:toggle_card, game_id, card, avatar, colour}, _from, state) do
    with {:ok, %GameTable{id: ^game_id, pid: game_pid}} <- lookup(game_id),
         :ok <- Game.toggle_card(game_pid, game_id, card, avatar, colour) do
      {:reply, :ok, state}
    else
      _ -> {:reply, {:error, :toggle_failed}, state}
    end
  end

  @impl true
  def handle_call({:deselect_all_cards, game_id}, _from, state) do
    with {:ok, %GameTable{id: ^game_id, pid: game_pid}} <- lookup(game_id),
         :ok <- Game.deselect_all_cards(game_pid, game_id) do
      {:reply, :ok, state}
    else
      _ -> {:reply, {:error, :deselect_all_failed}, state}
    end
  end

  @impl true
  def handle_call({:change_puzzle_date, game_id, %Date{} = new_date}, _from, state) do
    with {:ok, %GameTable{id: ^game_id, pid: game_pid}} <- lookup(game_id),
         :ok <- Game.change_puzzle_date(game_pid, game_id, new_date) do
      {:reply, :ok, state}
    else
      _ -> {:reply, {:error, :change_puzzle_date_failed}, state}
    end
  end

  @impl true
  def handle_call({:submit, game_id}, _from, state) do
    with {:ok, %GameTable{id: ^game_id, pid: game_pid}} <- lookup(game_id),
         :ok <- Game.submit(game_pid, game_id) do
      {:reply, :ok, state}
    else
      _ -> {:reply, {:error, :submit_failed}, state}
    end
  end

  @impl true
  def handle_call({:hint, game_id}, _from, state) do
    with {:ok, %GameTable{id: ^game_id, pid: game_pid}} <- lookup(game_id),
         :ok <- Game.hint(game_pid, game_id) do
      {:reply, :ok, state}
    else
      _ -> {:reply, {:error, :submit_failed}, state}
    end
  end

  @impl true
  def handle_call(:active_games_count, _from, state) do
    case all_rows() do
      {:ok, rows} -> {:reply, length(rows), state}
      _ -> {:reply, {:error, :could_not_get_active_games_count}, state}
    end
  end

  @impl true
  def handle_call(
        :active_players_count,
        _from,
        %{active_players: active_players} = state
      ) do
    {:reply, MapSet.size(active_players), state}
  end

  @impl true
  def handle_info(
        {ConnectionsMultiplayerWeb.Presence, {:join, %{id: presence_id}}},
        %{active_players: active_players} = state
      ) do
    new_state = %{state | active_players: MapSet.put(active_players, presence_id)}

    PubSub.broadcast(
      ConnectionsMultiplayer.PubSub,
      @registry_pubsub_topic,
      {__MODULE__, {:new_active_players_count, MapSet.size(new_state.active_players)}}
    )

    {:noreply, new_state}
  end

  @impl true
  def handle_info(
        {ConnectionsMultiplayerWeb.Presence, {:leave, %{id: presence_id, metas: metas}}},
        %{active_players: active_players} = state
      ) do
    if metas == [] do
      new_state = %{state | active_players: MapSet.delete(active_players, presence_id)}

      PubSub.broadcast(
        ConnectionsMultiplayer.PubSub,
        @registry_pubsub_topic,
        {__MODULE__, {:new_active_players_count, MapSet.size(new_state.active_players)}}
      )

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @spec calculate_active_players() ::
          {:ok, MapSet.t()} | {:error, :could_not_calculate_active_players}
  defp calculate_active_players do
    case all_rows() do
      {:ok, rows} ->
        rows
        |> Stream.map(fn %GameTable{id: game_id} -> game_id end)
        |> Stream.flat_map(&Presence.list_online_users/1)
        |> Stream.map(fn %{id: presence_id} -> presence_id end)
        |> MapSet.new()
        |> then(&{:ok, &1})

      _ ->
        {:error, :could_not_calculate_active_players}
    end
  end

  @spec create_new_game(String.t()) :: {:ok, map()} | {:error, :could_not_create_game}
  defp create_new_game(game_id) do
    with {:ok, new_game_pid} <- Game.start_link(),
         {:ok, game_state} <- Game.load(new_game_pid),
         {:ok, _} <- create_game_table_entry(game_id, new_game_pid) do
      {:ok, game_state}
    else
      _ ->
        {:error, :could_not_create_game}
    end
  end

  defp create_game_table_entry(game_id, game_pid) do
    Memento.transaction(fn ->
      Memento.Query.write(%GameTable{id: game_id, pid: game_pid})
    end)
  end

  @spec lookup(String.t()) :: {:ok, GameTable.t()} | {:error, any()}
  defp lookup(game_id) do
    Memento.transaction(fn ->
      Memento.Query.read(GameTable, game_id)
    end)
  end

  @spec all_rows() :: {:ok, [GameTable.t()]} | {:error, any()}
  defp all_rows do
    Memento.transaction(fn ->
      Memento.Query.all(GameTable)
    end)
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def load(game_id) do
    GenServer.call(__MODULE__, {:load, game_id})
  end

  def toggle_card(game_id, card, avatar, colour) do
    GenServer.call(__MODULE__, {:toggle_card, game_id, card, avatar, colour})
  end

  def deselect_all_cards(game_id) do
    GenServer.call(__MODULE__, {:deselect_all_cards, game_id})
  end

  def change_puzzle_date(game_id, %Date{} = new_date) do
    GenServer.call(__MODULE__, {:change_puzzle_date, game_id, new_date})
  end

  def submit(game_id) do
    GenServer.call(__MODULE__, {:submit, game_id})
  end

  def hint(game_id) do
    GenServer.call(__MODULE__, {:hint, game_id})
  end

  def active_games_count() do
    GenServer.call(__MODULE__, :active_games_count)
  end

  def active_players_count() do
    GenServer.call(__MODULE__, :active_players_count)
  end

  def subscribe(game_id) do
    PubSub.subscribe(ConnectionsMultiplayer.PubSub, "game:#{game_id}")
  end

  def subscribe_registry_updates() do
    PubSub.subscribe(ConnectionsMultiplayer.PubSub, @registry_pubsub_topic)
  end
end
