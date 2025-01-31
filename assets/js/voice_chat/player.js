let observers = new Set();

function createPlayerHook(iceServers = []) {
    return {
        async mounted() {
            observers.add(this.el);

            const audioPlayerWrapper = this.el.querySelector("#audio-player-wrapper");

            console.log(`${new Date().toISOString()}: Creating peer connection`);
            this.pc = new RTCPeerConnection({ iceServers: iceServers });

            this.pc.onicecandidate = (ev) => {
                console.log(`${new Date().toISOString()}: Sending ICE candidate`);
                this.pushEventTo(this.el, "ice", JSON.stringify(ev.candidate));
            };

            this.pc.ontrack = (event) => {
                console.log(`${new Date().toISOString()}: Received track, creating audio element`);

                const trackId = event.track.id;
                const audioPlayer = document.createElement('audio');
                audioPlayer.srcObject = event.streams[0];
                audioPlayer.autoplay = true;
                audioPlayer.muted = false;

                audioPlayerWrapper.appendChild(audioPlayer);

                event.track.onended = (_) => {
                    console.log(`${new Date().toISOString()}: Track ended: ${trackId}`);
                    audioPlayerWrapper.removeChild(audioPlayer);
                };
            };

            this.el.addEventListener("voice_chat_channel_connected", (event) => {
                console.log(`${new Date().toISOString()}: Voice chat channel connected: ${voiceChatChannel.topic}`);
                const voiceChatChannel = event.detail.voiceChatChannel;

                voiceChatChannel.push("soliciting-audio-offer", {}).receive("ok", (resp) => {
                    console.log(`${new Date().toISOString()}: Soliciting audio offer response: ${resp}`);
                })
            });

            // this.pc.addTransceiver("audio", { direction: "recvonly" });

            // const offer = await this.pc.createOffer();
            // await this.pc.setLocalDescription(offer);

            // const eventName = "answer" + "-" + this.el.id;
            // this.handleEvent(eventName, async (answer) => {
            //     await this.pc.setRemoteDescription(answer);
            // });

            // this.pushEventTo(this.el, "offer", offer);
        },

        async destroyed() {
            observers.delete(this.el);
        }
    };
}

function onVoiceChatChannelConnected(voiceChatChannel) {
    observers.forEach((observer) => {
        observer.dispatchEvent(new CustomEvent("voice_chat_channel_connected", { detail: { voiceChatChannel } }));
    })
}

export { createPlayerHook, onVoiceChatChannelConnected };