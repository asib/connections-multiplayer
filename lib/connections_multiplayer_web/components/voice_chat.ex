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
            publisher_to_audio_track_id: nil,
            enabled: false

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
    <div id={@publisher.id} phx-hook="VoiceChat" class="flex flex-col gap-2">
      <%!-- <div id="frequency-buttons">
        <button class="rounded-full p-3 bg-zinc-100 hover:bg-zinc-200/80">196</button>
        <button class="rounded-full p-3 bg-zinc-100 hover:bg-zinc-200/80">220</button>
        <button class="rounded-full p-3 bg-zinc-100 hover:bg-zinc-200/80">247</button>
      </div> --%>
      <div class="flex gap-2 self-end">
        <%!-- <button
          id="mute-microphone"
          class={[
            "rounded-full p-4 w-fit",
            if(@publisher.enabled, do: "inline-flex gap-2 items-center sm:block", else: "hidden"),
            if(@publisher.microphone_muted,
              do: "bg-red-800 hover:bg-red-800/90",
              else: "bg-gray-200 hover:bg-gray-200/80"
            )
          ]}
        >
          <p class={["sm:hidden", @publisher.microphone_muted && "text-white"]}>
            {if(@publisher.microphone_muted, do: "Unmute", else: "Mute")} microphone
          </p>
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            class="size-6"
          >
            <path
              id="microphone"
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M12 18.75a6 6 0 0 0 6-6v-1.5m-6 7.5a6 6 0 0 1-6-6v-1.5m6 7.5v3.75m-3.75 0h7.5M12 15.75a3 3 0 0 1-3-3V4.5a3 3 0 1 1 6 0v8.25a3 3 0 0 1-3 3Z"
              class={[if(@publisher.microphone_muted, do: "stroke-white", else: "stroke-black")]}
            />
            <path
              id="mute-line-margin"
              stroke-width="5"
              d="M2 1L22 22.5"
              class={["stroke-red-800", !@publisher.microphone_muted && "hidden"]}
            />
            <path
              id="mute-line"
              d="M2 1L22 22.5"
              class={["stroke-white", !@publisher.microphone_muted && "hidden"]}
            />
          </svg>
        </button> --%>
        <button
          id="toggle-voice-chat"
          class={[
            "rounded-full p-4 w-fit self-end text-white inline-flex gap-2 items-center sm:block",
            if(@publisher.enabled,
              do: "bg-red-600 sm:hover:bg-red-600/90",
              else: "bg-blue-600 sm:hover:bg-blue-600/90"
            )
          ]}
          aria-label={"#{if(@publisher.enabled, do: "Leave", else: "Join")} voice chat"}
        >
          <p class={["sm:hidden", @publisher.enabled && "text-white"]}>
            {if(@publisher.enabled, do: "Leave", else: "Join")} voice chat
          </p>
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class={["size-6 stroke-white", @publisher.enabled && "rotate-[135deg] translate-y-[2px]"]}
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M2.25 6.75c0 8.284 6.716 15 15 15h2.25a2.25 2.25 0 0 0 2.25-2.25v-1.372c0-.516-.351-.966-.852-1.091l-4.423-1.106c-.44-.11-.902.055-1.173.417l-.97 1.293c-.282.376-.769.542-1.21.38a12.035 12.035 0 0 1-7.143-7.143c-.162-.441.004-.928.38-1.21l1.293-.97c.363-.271.527-.734.417-1.173L6.963 3.102a1.125 1.125 0 0 0-1.091-.852H4.5A2.25 2.25 0 0 0 2.25 4.5v2.25Z"
            />
          </svg>
        </button>
      </div>
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
        {:packet, _params},
        %{assigns: %{publisher: %__MODULE__{is_negotiating_setup?: true}}} = socket
      ) do
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

  @impl true
  def handle_event("toggle-voice-chat", %{"enabled" => enabled}, socket) do
    %{publisher: publisher} = socket.assigns

    {:noreply, assign(socket, :publisher, %{publisher | enabled: enabled})}
  end

  # @impl true
  # def handle_event("toggle-mute-microphone", %{"enabled" => enabled}, socket) do
  #   %{publisher: publisher} = socket.assigns

  #   {:noreply, assign(socket, :publisher, %{publisher | microphone_muted: !enabled})}
  # end

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
