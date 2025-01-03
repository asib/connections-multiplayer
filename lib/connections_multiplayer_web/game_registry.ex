defmodule ConnectionsMultiplayerWeb.GameRegistry do
  use GenServer

  alias Phoenix.PubSub
  alias ConnectionsMultiplayerWeb.Game

  @impl true
  def init(_) do
    tid = :ets.new(:game_registry, [:named_table, :public, write_concurrency: true])

    {:ok, tid}
  end

  @impl true
  def handle_call({:load, game_id}, _from, tid) do
    with [{^game_id, game_pid}] <- :ets.lookup(tid, game_id),
         {:ok, game_state} <- Game.load(game_pid) do
      {:reply, {:ok, game_state}, tid}
    else
      _ ->
        {:reply, create_new_game(tid, game_id), tid}
    end
  end

  @impl true
  def handle_call({:toggle_card, game_id, card, avatar, colour}, _from, tid) do
    with [{^game_id, game_pid}] <- :ets.lookup(tid, game_id),
         :ok <- Game.toggle_card(game_pid, game_id, card, avatar, colour) do
      {:reply, :ok, tid}
    else
      _ -> {:reply, {:error, :toggle_failed}, tid}
    end
  end

  @impl true
  def handle_call({:deselect_all_cards, game_id}, _from, tid) do
    with [{^game_id, game_pid}] <- :ets.lookup(tid, game_id),
         :ok <- Game.deselect_all_cards(game_pid, game_id) do
      {:reply, :ok, tid}
    else
      _ -> {:reply, {:error, :deselect_all_failed}, tid}
    end
  end

  @impl true
  def handle_call({:change_puzzle_date, game_id, %Date{} = new_date}, _from, tid) do
    with [{^game_id, game_pid}] <- :ets.lookup(tid, game_id),
         :ok <- Game.change_puzzle_date(game_pid, game_id, new_date) do
      {:reply, :ok, tid}
    else
      _ -> {:reply, {:error, :change_puzzle_date_failed}, tid}
    end
  end

  @impl true
  def handle_call({:submit, game_id}, _from, tid) do
    with [{^game_id, game_pid}] <- :ets.lookup(tid, game_id),
         :ok <- Game.submit(game_pid, game_id) do
      {:reply, :ok, tid}
    else
      _ -> {:reply, {:error, :submit_failed}, tid}
    end
  end

  @impl true
  def handle_call({:hint, game_id}, _from, tid) do
    with [{^game_id, game_pid}] <- :ets.lookup(tid, game_id),
         :ok <- Game.hint(game_pid, game_id) do
      {:reply, :ok, tid}
    else
      _ -> {:reply, {:error, :submit_failed}, tid}
    end
  end

  defp create_new_game(tid, game_id) do
    with {:ok, new_game_pid} <- Game.start_link(),
         {:ok, game_state} <- Game.load(new_game_pid),
         true <- :ets.insert(tid, {game_id, new_game_pid}) do
      {:ok, game_state}
    else
      _ ->
        {:error, :could_not_create_game}
    end
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

  def subscribe(game_id) do
    PubSub.subscribe(ConnectionsMultiplayer.PubSub, "game:#{game_id}")
  end
end
