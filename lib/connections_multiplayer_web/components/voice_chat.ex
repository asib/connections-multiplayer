defmodule ConnectionsMultiplayerWeb.VoiceChat do
  use ConnectionsMultiplayerWeb, :live_view

  require Logger

  alias ExWebRTC.{ICECandidate, MediaStreamTrack, PeerConnection, SessionDescription}
  alias ConnectionsMultiplayerWeb.VoiceChatMux

  @type t() :: struct()

  defstruct id: nil,
            pc: nil,
            audio_track_id: nil,
            pubsub: nil,
            ice_servers: nil,
            ice_ip_filter: nil,
            ice_port_range: nil,
            audio_codecs: nil,
            pc_genserver_opts: nil,
            is_negotiating_setup?: true,
            pending_publisher_pids: [],
            publisher_to_audio_track_id: nil

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
        :ice_servers,
        :ice_ip_filter,
        :ice_port_range,
        :audio_codecs,
        :pc_genserver_opts
      ])

    publisher = %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      pubsub: Keyword.fetch!(opts, :pubsub),
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
    <div id={@publisher.id} phx-hook="VoiceChat" class="fixed bottom-4 right-4 flex flex-col gap-2">
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
      <div id="audio-player-wrapper"></div>
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

    :ok =
      VoiceChatMux.broadcast_packet(socket.assigns.room_id, publisher.pc, publisher.id, packet)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:ex_webrtc, _, _}, socket) do
    {:noreply, socket}
  end

  def handle_info(
        {:packet, %{publisher_id: publisher_id, packet: packet, publisher_pid: publisher_pid}},
        socket
      ) do
    %{publisher: publisher} = socket.assigns

    if publisher.id != publisher_id do
      case publisher.publisher_to_audio_track_id[publisher_pid] do
        nil ->
          Logger.error(
            "#{__MODULE__} #{inspect(self())}: received audio packet from #{inspect(publisher_pid)} but no audio track id found: #{inspect(publisher.publisher_to_audio_track_id)}, #{inspect(publisher.pending_publisher_pids)}"
          )

        audio_track_id ->
          PeerConnection.send_rtp(publisher.pc, audio_track_id, packet)
      end
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:publisher_added, publisher_pid},
        %{assigns: %{publisher: %__MODULE__{pc: publisher_pid}}} = socket
      ) do
    # We got a notification about ourselves being added to voice chat, ignore
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:publisher_added, publisher_pid},
        %{assigns: %{publisher: %__MODULE__{is_negotiating_setup?: true}}} = socket
      ) do
    {:noreply,
     assign(socket, :publisher, %{
       socket.assigns.publisher
       | pending_publisher_pids: [
           socket.assigns.publisher.pending_publisher_pids | publisher_pid
         ]
     })}
  end

  @impl true
  def handle_info(
        {:publisher_added, publisher_pid},
        %{assigns: %{publisher: %__MODULE__{is_negotiating_setup?: false}}} = socket
      ) do
    Logger.info("#{__MODULE__} #{inspect(self())}: adding publisher #{inspect(publisher_pid)}")
    %{publisher: publisher} = socket.assigns

    audio_track_id = add_new_audio_track(publisher.pc)
    {:ok, offer} = PeerConnection.create_offer(publisher.pc)
    PeerConnection.set_local_description(publisher.pc, offer)

    new_publisher = %__MODULE__{
      publisher
      | publisher_to_audio_track_id:
          Map.put(publisher.publisher_to_audio_track_id, publisher_pid, audio_track_id)
    }

    {:noreply,
     assign(socket, :publisher, new_publisher)
     |> push_event("offer-#{publisher.id}", SessionDescription.to_json(offer))}
  end

  @impl true
  def handle_info({:publisher_removed, publisher_pid}, socket) do
    %{publisher: publisher} = socket.assigns

    new_publisher =
      with {:get_audio_track_id, track_id} when track_id != nil <-
             {:get_audio_track_id, publisher.publisher_to_audio_track_id[publisher_pid]},
           {:get_transceiver_for_audio_track, transceiver} when transceiver != nil <-
             {:get_transceiver_for_audio_track,
              publisher.pc
              |> PeerConnection.get_transceivers()
              |> Enum.find(fn transceiver -> get_in(transceiver.sender.track.id) == track_id end)} do
        Logger.info("#{__MODULE__} #{inspect(self())}: removing track")

        :ok = PeerConnection.remove_track(publisher.pc, transceiver.sender.id)

        %__MODULE__{
          publisher
          | publisher_to_audio_track_id:
              Map.delete(publisher.publisher_to_audio_track_id, publisher_pid)
        }
      else
        error ->
          Logger.error(
            "#{__MODULE__} #{inspect(self())}: error removing track for publisher #{inspect(publisher_pid)}: #{inspect(error)}"
          )

          publisher
      end

    {:noreply, assign(socket, :publisher, new_publisher)}
  end

  @impl true
  def handle_event("offer", unsigned_params, socket) do
    %{publisher: publisher} = socket.assigns
    offer = SessionDescription.from_json(unsigned_params)
    {:ok, pc} = spawn_peer_connection(socket)
    :ok = PeerConnection.set_remote_description(pc, offer)

    [%{kind: :audio, receiver: %{track: audio_track}}] = PeerConnection.get_transceivers(pc)

    {:ok, publishers} = VoiceChatMux.get_publishers_for_game(socket.assigns.room_id)
    publisher_to_audio_track_id = Map.new(publishers, &{&1, add_new_audio_track(pc)})

    {:ok, answer} = PeerConnection.create_answer(pc)
    :ok = PeerConnection.set_local_description(pc, answer)
    :ok = gather_candidates(pc)
    answer = PeerConnection.get_local_description(pc)

    new_publisher = %__MODULE__{
      publisher
      | pc: pc,
        audio_track_id: audio_track.id,
        publisher_to_audio_track_id: publisher_to_audio_track_id,
        is_negotiating_setup?: true
    }

    :ok = VoiceChatMux.add_publisher_to_game(socket.assigns.room_id, pc)
    :ok = VoiceChatMux.subscribe(socket.assigns.room_id)

    {:noreply,
     socket
     |> assign(publisher: new_publisher)
     |> push_event("answer-#{publisher.id}", SessionDescription.to_json(answer))}
  end

  @impl true
  def handle_event("answer", unsigned_params, socket) do
    %{publisher: publisher} = socket.assigns

    offer = SessionDescription.from_json(unsigned_params)
    :ok = PeerConnection.set_remote_description(publisher.pc, offer)

    {:noreply, socket}
  end

  @impl true
  def handle_event("initial-negotiation-complete", _params, socket) do
    %{publisher: publisher} = socket.assigns

    Logger.info(
      "#{__MODULE__} #{inspect(self())}: initial negotiation complete, adding pending publishers"
    )

    new_publishers_to_audio_track_ids =
      Enum.reduce(publisher.pending_publisher_pids, %{}, fn publisher_pid, acc ->
        Logger.info(
          "#{__MODULE__} #{inspect(self())}: adding publisher #{inspect(publisher_pid)}"
        )

        audio_track_id = add_new_audio_track(publisher.pc)
        Map.put(acc, publisher_pid, audio_track_id)
      end)

    new_publisher = %__MODULE__{
      publisher
      | publisher_to_audio_track_id:
          Map.merge(publisher.publisher_to_audio_track_id, new_publishers_to_audio_track_ids),
        is_negotiating_setup?: false
    }

    {:ok, offer} = PeerConnection.create_offer(publisher.pc)
    :ok = PeerConnection.set_local_description(publisher.pc, offer)

    {:noreply, assign(socket, :publisher, new_publisher)}
  end

  @impl true
  def handle_event("ice", "null", socket) do
    %{publisher: publisher} = socket.assigns

    case publisher do
      %__MODULE__{pc: nil} ->
        {:noreply, socket}

      %__MODULE__{pc: pc} ->
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

    PeerConnection.start_link(pc_opts, publisher.pc_genserver_opts)
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

  defp add_new_audio_track(pc) do
    stream_id = MediaStreamTrack.generate_stream_id()
    audio_track = MediaStreamTrack.new(:audio, [stream_id])
    {:ok, _sender} = PeerConnection.add_track(pc, audio_track)

    audio_track.id
  end
end
