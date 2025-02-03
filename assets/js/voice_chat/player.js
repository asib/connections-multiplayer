export function createPlayerHook(iceServers = []) {
    return {
        async mounted() {
            const audioPlayerWrapper = this.el.querySelector("#audio-player-wrapper");

            this.setupMuteButton();

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
            }

            this.pc.onnegotiationneeded = (ev) => {
                console.log(`${new Date().toISOString()}: Negotiation needed: ${JSON.stringify(ev)}`);
            };

            const eventName = "answer" + "-" + this.el.id;
            this.handleEvent(eventName, async (answer) => {
                console.log(`${new Date().toISOString()}: Got offer answer`);
                await this.pc.setRemoteDescription(answer);

                console.log(`${new Date().toISOString()}: Pushing negotiation complete`);
                this.pushEventTo(this.el, "negotiation-complete", {});
            });

            console.log(`${new Date().toISOString()}: Soliciting offer`);
            this.pushEventTo(this.el, "soliciting-offer", {}, async ({ num_transceivers }) => {
                console.log(`${new Date().toISOString()}: Adding ${num_transceivers} transceivers`);
                for (let i = 0; i < num_transceivers; i++) {
                    this.pc.addTransceiver("audio", { direction: "recvonly" });
                }

                const offer = await this.pc.createOffer({ offerToReceiveAudio: true });
                await this.pc.setLocalDescription(offer);

                console.log(`${new Date().toISOString()}: Pushing offer`);
                this.pushEventTo(this.el, "offer", offer);
            });
        },

        setupMuteButton() {
            this.el.querySelector("#toggle-mute").addEventListener("click", () => {
                this.el.querySelectorAll("#audio-player-wrapper>audio").forEach((audio) => {
                    audio.muted = !audio.muted;
                });
            });
        }
    };
}