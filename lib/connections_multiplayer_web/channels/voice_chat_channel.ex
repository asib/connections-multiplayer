defmodule ConnectionsMultiplayerWeb.VoiceChatChannel do
  use ConnectionsMultiplayerWeb, :channel

  @impl true
  def join("voice_chat:" <> _game_id, _params, socket) do
    # send(self(), :after_join)
    {:ok, socket}
  end

  @impl true
  def handle_in("soliciting-audio-offer", _payload, socket) do
    {:reply, {:ok, %{}}, socket}
  end

  # @impl true
  # def handle_info(:after_join, socket) do
  #   {:noreply, socket}
  # end
end
