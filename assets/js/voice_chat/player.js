export function createPlayerHook(iceServers = []) {
    return {
        async mounted() {
            const audioPlayerWrapper = this.el.querySelector("#audio-player-wrapper");

            this.setupMuteButton();

            console.log(`${new Date().toISOString()}: creating peer connection`);
            this.pc = new RTCPeerConnection({ iceServers: iceServers });
            this.pc.addTransceiver("audio", { direction: "recvonly" });

            this.pc.onicecandidate = (ev) => {
                console.log(`${new Date().toISOString()}: sending ICE candidate`);
                this.pushEventTo(this.el, "ice", JSON.stringify(ev.candidate));
            };

            this.pc.ontrack = (event) => {
                console.log(`${new Date().toISOString()}: received track, creating audio element`);

                const trackId = event.track.id;
                const audioPlayer = document.createElement('audio');
                audioPlayer.srcObject = event.streams[0];
                audioPlayer.autoplay = true;
                audioPlayer.muted = false;

                audioPlayerWrapper.appendChild(audioPlayer);

                event.track.onended = (_) => {
                    console.log(`${new Date().toISOString()}: track ended: ${trackId}`);
                    audioPlayerWrapper.removeChild(audioPlayer);
                    this.pc.getSenders().filter((sender) => sender.track?.id === trackId).forEach((sender) => {
                        this.pc.removeTrack(sender);
                    })
                }
            }

            this.handleEvent(`answer-${this.el.id}`, async (answer) => {
                console.log(`${new Date().toISOString()}: got offer answer`);
                await this.pc.setRemoteDescription(answer);

                console.log(`${new Date().toISOString()}: confirming negotiation complete`);
                this.pushEventTo(this.el, "negotiation-complete", {});
            });

            this.handleEvent(`offer-${this.el.id}`, async (offer) => {
                console.log(`${new Date().toISOString()}: got offer`);
                await this.pc.setRemoteDescription(offer);

                const answer = await this.pc.createAnswer();
                await this.pc.setLocalDescription(answer);

                console.log(`${new Date().toISOString()}: sending answer`);
                this.pushEventTo(this.el, "answer", answer);
            });

            const offer = await this.pc.createOffer();
            await this.pc.setLocalDescription(offer);

            console.log(`${new Date().toISOString()}: sending offer`);
            this.pushEventTo(this.el, "offer", offer);
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