defmodule ConnectionsMultiplayerWeb.VoiceChat.Publisher do
  alias ConnectionsMultiplayerWeb.VoiceChatMux
  use ConnectionsMultiplayerWeb, :live_view

  alias ExWebRTC.{ICECandidate, PeerConnection, SessionDescription}
  alias Phoenix.PubSub

  require Logger

  @type on_connected() :: (publisher_id :: String.t() -> any())

  @type on_packet() ::
          (publisher_id :: String.t(),
           packet_type :: :audio | :video,
           packet :: ExRTP.Packet.t(),
           socket :: Phoenix.LiveView.Socket.t() ->
             packet :: ExRTP.Packet.t())

  @type t() :: struct()

  defstruct id: nil,
            pc: nil,
            audio_track_id: nil,
            on_packet: nil,
            on_connected: nil,
            pubsub: nil,
            ice_servers: nil,
            ice_ip_filter: nil,
            ice_port_range: nil,
            audio_codecs: nil,
            pc_genserver_opts: nil

  attr(:socket, Phoenix.LiveView.Socket, required: true, doc: "Parent live view socket")

  attr(:publisher, __MODULE__,
    required: true,
    doc: """
    Publisher struct. It is used to pass publisher id to the newly created live view via live view session.
    This data is then used to do a handshake between parent live view and child live view during which child live
    view receives the whole Publisher struct.
    """
  )

  attr(:room_id, :string, required: true, doc: "Voice chat room id")

  def live_render(assigns) do
    ~H"""
    {live_render(@socket, __MODULE__,
      id: "#{@publisher.id}-lv",
      session: %{"publisher_id" => @publisher.id, "room_id" => @room_id}
    )}
    """
  end

  @spec attach(Phoenix.LiveView.Socket.t(), Keyword.t()) :: Phoenix.LiveView.Socket.t()
  def attach(socket, opts) do
    opts =
      Keyword.validate!(opts, [
        :id,
        :name,
        :pubsub,
        :on_packet,
        :on_connected,
        :ice_servers,
        :ice_ip_filter,
        :ice_port_range,
        :audio_codecs,
        :pc_genserver_opts
      ])

    publisher = %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      pubsub: Keyword.fetch!(opts, :pubsub),
      on_packet: Keyword.get(opts, :on_packet),
      on_connected: Keyword.get(opts, :on_connected),
      ice_servers: Keyword.get(opts, :ice_servers, [%{urls: "stun:stun.l.google.com:19302"}]),
      ice_ip_filter: Keyword.get(opts, :ice_ip_filter),
      ice_port_range: Keyword.get(opts, :ice_port_range),
      audio_codecs: Keyword.get(opts, :audio_codecs),
      pc_genserver_opts: Keyword.get(opts, :pc_genserver_opts, [])
    }

    socket
    |> assign(publisher: publisher)
    |> attach_hook(:publisher_handshake, :handle_info, &handshake/2)
  end

  defp handshake({__MODULE__, {:connected, ref, pid, _meta}}, socket) do
    send(pid, {ref, socket.assigns.publisher})
    {:halt, socket}
  end

  defp handshake(_msg, socket) do
    {:cont, socket}
  end

  ## CALLBACKS

  @impl true
  def render(%{publisher: nil} = assigns) do
    ~H"""
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@publisher.id} phx-hook="Publisher" class="fixed bottom-4 right-4 flex flex-col gap-2">
      <div id="frequency-buttons">
        <button class="rounded-full p-3 bg-zinc-100 hover:bg-zinc-200/80">196</button>
        <button class="rounded-full p-3 bg-zinc-100 hover:bg-zinc-200/80">220</button>
        <button class="rounded-full p-3 bg-zinc-100 hover:bg-zinc-200/80">247</button>
      </div>
      <button
        id="toggle-voice-chat"
        class="rounded-full p-3 bg-zinc-100 hover:bg-zinc-200/80 w-fit self-end"
        aria-label="Toggle voice chat"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="w-6 h-6"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M12 18.75a6 6 0 006-6v-1.5m-6 7.5a6 6 0 01-6-6v-1.5m6 7.5v3.75m-3.75 0h7.5M12 15.75a3 3 0 01-3-3V4.5a3 3 0 116 0v8.25a3 3 0 01-3 3z"
          />
        </svg>
      </button>
    </div>
    """
  end

  @impl true
  def mount(_params, %{"publisher_id" => pub_id, "room_id" => room_id}, socket) do
    socket = assign(socket, publisher: nil, room_id: room_id)

    if connected?(socket) do
      ref = make_ref()
      send(socket.parent_pid, {__MODULE__, {:connected, ref, self(), %{publisher_id: pub_id}}})

      socket =
        receive do
          {^ref, %__MODULE__{id: ^pub_id} = publisher} -> assign(socket, publisher: publisher)
        after
          5000 -> exit(:timeout)
        end

      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:rtp, track_id, nil, packet}}, socket) do
    %{publisher: %__MODULE__{audio_track_id: ^track_id} = publisher} = socket.assigns

    Logger.info(
      "#{__MODULE__} #{inspect(self())}: broadcasting audio packet to #{socket.assigns.room_id}"
    )

    PubSub.broadcast(
      publisher.pubsub,
      "streams:audio:#{socket.assigns.room_id}",
      {:live_ex_webrtc, :audio, publisher.id, packet}
    )

    if publisher.on_packet, do: publisher.on_packet.(publisher.id, :audio, packet, socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:ex_webrtc, _pid, {:connection_state_change, :connected}}, socket) do
    %{publisher: pub} = socket.assigns
    if pub.on_connected, do: pub.on_connected.(pub.id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:ex_webrtc, _, _}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("offer", unsigned_params, socket) do
    Logger.info("#{__MODULE__} #{inspect(self())}: received offer")

    %{publisher: publisher} = socket.assigns
    offer = SessionDescription.from_json(unsigned_params)
    Logger.info("#{__MODULE__} #{inspect(self())}: creating peer connection")
    {:ok, pc} = spawn_peer_connection(socket)
    Logger.info("#{__MODULE__} #{inspect(self())}: setting remote description")
    :ok = PeerConnection.set_remote_description(pc, offer)

    [%{kind: :audio, receiver: %{track: audio_track}}] = PeerConnection.get_transceivers(pc)

    Logger.info("#{__MODULE__} #{inspect(self())}: creating answer")
    {:ok, answer} = PeerConnection.create_answer(pc)
    Logger.info("#{__MODULE__} #{inspect(self())}: setting local description")
    :ok = PeerConnection.set_local_description(pc, answer)
    Logger.info("#{__MODULE__} #{inspect(self())}: gathering candidates")
    :ok = gather_candidates(pc)
    Logger.info("#{__MODULE__} #{inspect(self())}: getting local description")
    answer = PeerConnection.get_local_description(pc)

    new_publisher = %__MODULE__{
      publisher
      | pc: pc,
        audio_track_id: audio_track.id
    }

    Logger.info("#{__MODULE__} #{inspect(self())}: pushing answer")

    VoiceChatMux.add_publisher_to_game(socket.assigns.room_id, pc)

    {:noreply,
     socket
     |> assign(publisher: new_publisher)
     |> push_event("answer-#{publisher.id}", SessionDescription.to_json(answer))}
  end

  @impl true
  def handle_event("ice", "null", socket) do
    %{publisher: publisher} = socket.assigns

    case publisher do
      %__MODULE__{pc: nil} ->
        {:noreply, socket}

      %__MODULE__{pc: pc} ->
        Logger.info("#{__MODULE__} #{inspect(self())}: adding ice candidate: null")
        :ok = PeerConnection.add_ice_candidate(pc, %ICECandidate{candidate: ""})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("ice", unsigned_params, socket) do
    %{publisher: publisher} = socket.assigns

    case publisher do
      %__MODULE__{pc: nil} ->
        {:noreply, socket}

      %__MODULE__{pc: pc} ->
        cand =
          unsigned_params
          |> Jason.decode!()
          |> ExWebRTC.ICECandidate.from_json()

        Logger.info("#{__MODULE__} #{inspect(self())}: adding ice candidate: #{cand.candidate}")
        :ok = PeerConnection.add_ice_candidate(pc, cand)

        {:noreply, socket}
    end
  end

  defp spawn_peer_connection(socket) do
    %{publisher: publisher} = socket.assigns

    pc_opts =
      [
        ice_servers: publisher.ice_servers,
        ice_ip_filter: publisher.ice_ip_filter,
        ice_port_range: publisher.ice_port_range,
        audio_codecs: publisher.audio_codecs
      ]
      |> Enum.reject(fn {_k, v} -> v == nil end)

    PeerConnection.start(pc_opts, publisher.pc_genserver_opts)
  end

  defp gather_candidates(pc) do
    # we either wait for all of the candidates
    # or whatever we were able to gather in one second
    receive do
      {:ex_webrtc, ^pc, {:ice_gathering_state_change, :complete}} -> :ok
    after
      1000 -> :ok
    end
  end
end
