defmodule ConnectionsMultiplayerWeb.VoiceChat.Player do
  use ConnectionsMultiplayerWeb, :live_view

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
            publisher_id: nil,
            pubsub: nil,
            pc: nil,
            audio_track_id: nil,
            on_packet: nil,
            on_connected: nil,
            ice_servers: nil,
            ice_ip_filter: nil,
            ice_port_range: nil,
            audio_codecs: nil,
            pc_genserver_opts: nil

  alias ExWebRTC.{ICECandidate, MediaStreamTrack, PeerConnection, SessionDescription}
  alias Phoenix.PubSub

  attr(:socket, Phoenix.LiveView.Socket, required: true, doc: "Parent live view socket")

  attr(:player, __MODULE__,
    required: true,
    doc: """
    Player struct. It is used to pass player id and publisher id to the newly created live view via live view session.
    This data is then used to do a handshake between parent live view and child live view during which child live view receives
    the whole Player struct.
    """
  )

  attr(:room_id, :string, required: true, doc: "Voice chat room id")

  attr(:class, :string, default: nil, doc: "CSS/Tailwind classes for styling HTMLVideoElement")

  @doc """
  Helper function for rendering Player live view.
  """
  def live_render(assigns) do
    ~H"""
    {live_render(@socket, __MODULE__,
      id: "#{@player.id}-lv",
      session: %{
        "publisher_id" => @player.publisher_id,
        "room_id" => @room_id,
        "class" => @class
      }
    )}
    """
  end

  @doc """
  Attaches required hooks and creates `t:t/0` struct.

  Created struct is saved in socket's assigns and has to be passed to `LiveExWebRTC.Player.live_render/1`.

  Options:
  * `id` - player id. This is typically your user id (if there is users database).
  It is used to identify live view and generated HTML video player.
  * `publisher_id` - publisher id that this player is going to subscribe to.
  * `pubsub` - a pubsub that player live view will subscribe to for audio and video packets. See module doc for more.
  * `on_connected` - callback called when the underlying peer connection changes its state to the `:connected`. See `t:on_connected/0`.
  * `on_packet` - callback called for each audio and video RTP packet. Can be used to modify the packet before sending via WebRTC to the other side. See `t:on_packet/0`.
  * `ice_servers` - a list of `t:ExWebRTC.PeerConnection.Configuration.ice_server/0`,
  * `ice_ip_filter` - `t:ExICE.ICEAgent.ip_filter/0`,
  * `ice_port_range` - `t:Enumerable.t(non_neg_integer())/1`,
  * `audio_codecs` - a list of `t:ExWebRTC.RTPCodecParameters.t/0`,
  * `pc_genserver_opts` - `t:GenServer.options/0` for the underlying `ExWebRTC.PeerConnection` process.
  * `class` - a list of CSS/Tailwind classes that will be applied to the HTMLVideoPlayer. Defaults to "".
  """
  @spec attach(Phoenix.LiveView.Socket.t(), Keyword.t()) :: Phoenix.LiveView.Socket.t()
  def attach(socket, opts) do
    opts =
      Keyword.validate!(opts, [
        :id,
        :publisher_id,
        :pc_genserver_opts,
        :pubsub,
        :on_connected,
        :on_packet,
        :ice_servers,
        :ice_ip_filter,
        :ice_port_range,
        :audio_codecs
      ])

    player = %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      publisher_id: Keyword.fetch!(opts, :publisher_id),
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
    |> assign(player: player)
    |> attach_hook(:player_handshake, :handle_info, &handshake/2)
  end

  defp handshake({__MODULE__, {:connected, ref, child_pid, _meta}}, socket) do
    # child live view is connected, send it player struct
    send(child_pid, {ref, socket.assigns.player})
    {:halt, socket}
  end

  defp handshake(_msg, socket) do
    {:cont, socket}
  end

  ## CALLBACKS

  @impl true
  def render(%{player: nil} = assigns) do
    ~H"""
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@player.id} phx-hook="Player" class="fixed bottom-4 right-[4.5rem] flex flex-col">
      <div id="audio-player-wrapper">
        <button
          id="toggle-mute"
          class="rounded-full p-3 bg-zinc-100 hover:bg-zinc-200/80"
          aria-label="Toggle mute"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="size-6"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M19.114 5.636a9 9 0 010 12.728M16.463 8.288a5.25 5.25 0 010 7.424M6.75 8.25l4.72-4.72a.75.75 0 011.28.53v15.88a.75.75 0 01-1.28.53l-4.72-4.72H4.51c-.88 0-1.704-.507-1.938-1.354A9.01 9.01 0 012.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75z"
            />
          </svg>
        </button>
        <%!-- <audio id={@player.id} phx-hook="Player" class={@class} autoplay></audio> --%>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, %{"publisher_id" => pub_id, "class" => class, "room_id" => room_id}, socket) do
    socket =
      assign(socket, class: class, player: nil, room_id: room_id, last_sequence_number: nil)

    if connected?(socket) do
      ref = make_ref()
      send(socket.parent_pid, {__MODULE__, {:connected, ref, self(), %{publisher_id: pub_id}}})

      socket =
        receive do
          {^ref, %__MODULE__{publisher_id: ^pub_id} = player} ->
            assign(socket, player: player)
        after
          5000 -> exit(:timeout)
        end

      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_info({:ex_webrtc, _pid, {:connection_state_change, :connected}}, socket) do
    %{player: player} = socket.assigns

    Logger.info("#{__MODULE__} #{inspect(self())}: subscribing to pubsub")

    PubSub.subscribe(
      player.pubsub,
      "streams:audio:#{socket.assigns.room_id}"
    )

    if player.on_connected, do: player.on_connected.(player.publisher_id)

    {:noreply, socket}
  end

  def handle_info({:ex_webrtc, _pid, _}, socket) do
    {:noreply, socket}
  end

  def handle_info({:live_ex_webrtc, :audio, publisher_id, packet}, socket) do
    %{player: player} = socket.assigns

    %{sequence_number: sequence_number} = packet

    {socket, packet} =
      if socket.assigns.last_sequence_number == nil do
        {assign(socket, last_sequence_number: sequence_number), packet}
      else
        new_last_sequence_number = socket.assigns.last_sequence_number + 1

        {assign(socket, last_sequence_number: new_last_sequence_number),
         %{packet | sequence_number: new_last_sequence_number}}
      end

    if player.publisher_id != publisher_id do
      Logger.info("#{__MODULE__} #{inspect(self())}: received audio packet from #{publisher_id}")

      packet =
        if player.on_packet,
          do: player.on_packet.(player.publisher_id, :audio, packet, socket),
          else: packet

      dbg(packet)
      PeerConnection.send_rtp(player.pc, player.audio_track_id, packet)
    else
      Logger.info("#{__MODULE__} #{inspect(self())}: received audio packet from self")
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("offer", unsigned_params, socket) do
    %{player: player} = socket.assigns

    offer = SessionDescription.from_json(unsigned_params)
    Logger.info("#{__MODULE__} #{inspect(self())}: creating peer connection")
    {:ok, pc} = spawn_peer_connection(socket)
    Logger.info("#{__MODULE__} #{inspect(self())}: setting remote description")
    :ok = PeerConnection.set_remote_description(pc, offer)

    stream_id = MediaStreamTrack.generate_stream_id()
    audio_track = MediaStreamTrack.new(:audio, [stream_id])
    Logger.info("#{__MODULE__} #{inspect(self())}: adding track")
    {:ok, _sender} = PeerConnection.add_track(pc, audio_track)
    Logger.info("#{__MODULE__} #{inspect(self())}: creating answer")
    {:ok, answer} = PeerConnection.create_answer(pc)
    Logger.info("#{__MODULE__} #{inspect(self())}: setting local description")
    :ok = PeerConnection.set_local_description(pc, answer)
    Logger.info("#{__MODULE__} #{inspect(self())}: gathering candidates")
    :ok = gather_candidates(pc)
    Logger.info("#{__MODULE__} #{inspect(self())}: getting local description")
    answer = PeerConnection.get_local_description(pc)

    new_player = %__MODULE__{
      player
      | pc: pc,
        audio_track_id: audio_track.id
    }

    Logger.info("#{__MODULE__} #{inspect(self())}: pushing answer")

    {:noreply,
     socket
     |> assign(player: new_player)
     |> push_event("answer-#{player.id}", SessionDescription.to_json(answer))}
  end

  @impl true
  def handle_event("ice", "null", socket) do
    %{player: player} = socket.assigns

    case player do
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
    %{player: player} = socket.assigns

    case player do
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
    %{player: player} = socket.assigns

    pc_opts =
      [
        ice_servers: player.ice_servers,
        ice_ip_filter: player.ice_ip_filter,
        ice_port_range: player.ice_port_range,
        audio_codecs: player.audio_codecs
      ]
      |> Enum.reject(fn {_k, v} -> v == nil end)

    PeerConnection.start_link(pc_opts, player.pc_genserver_opts)
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
