export function createVoiceChatHook(iceServers = []) {
    return {
        async mounted() {
            this.audioPlayerWrapper = this.el.querySelector("#audio-player-wrapper");

            this.el.querySelectorAll("#frequency-buttons>button").forEach((button) => {
                button.addEventListener("click", () => {
                    const frequency = parseInt(button.textContent);
                    this.pc.getSenders()[0].replaceTrack(this.createSineWaveTrack(frequency));
                });
            });

            this.toggleVoiceChatButton = document.getElementById("toggle-voice-chat");
            this.toggleVoiceChatButton.addEventListener("click", async () => {
                if (this.pc === undefined) {
                    await this.startStreaming();

                    this.el.dataset.streaming = "true";

                    this.toggleVoiceChatButton.classList.remove("bg-zinc-100", "hover:bg-zinc-200/80");
                    this.toggleVoiceChatButton.classList.add("bg-green-300", "hover:bg-green-400/80");
                } else {
                    this.stopStreaming();

                    this.el.dataset.streaming = "false";

                    this.toggleVoiceChatButton.classList.remove("bg-green-300", "hover:bg-green-400/80");
                    this.toggleVoiceChatButton.classList.add("bg-zinc-100", "hover:bg-zinc-200/80");
                }
            });

            // handle remote events
            this.handleEvent(`offer-${this.el.id}`, async (offer) => {
                console.log(`${new Date().toISOString()}: got offer`);
                await this.pc.setRemoteDescription(offer);

                const answer = await this.pc.createAnswer();
                await this.pc.setLocalDescription(answer);

                console.log(`${new Date().toISOString()}: sending answer`);
                this.pushEventTo(this.el, "answer", answer);
            });

            this.handleEvent(`answer-${this.el.id}`, async (answer) => {
                if (this.pc) {
                    console.log(`${new Date().toISOString()}: Setting remote description`);
                    await this.pc.setRemoteDescription(answer);
                    this.pushEventTo(this.el, "initial-negotiation-complete", {});
                } else {
                    console.warn(`${new Date().toISOString()}: Received SDP cnswer but there is no PC. Ignoring.`);
                }
            });

            this.handleEvent(`ice-${this.el.id}`, async (cand) => {
                if (this.pc) {
                    console.log(`${new Date().toISOString()}: Adding ICE candidate`);
                    await this.pc.addIceCandidate(JSON.parse(cand));
                } else {
                    console.warn(`${new Date().toISOString()}: Received ICE candidate but there is no PC. Ignoring.`);
                }
            });
        },

        async startStreaming() {
            if (this.localStream != undefined) {
                this.stopStreaming(this);
            }

            console.log(`${new Date().toISOString()}: Setting up local stream`);
            this.localStream = await window.navigator.mediaDevices.getUserMedia({
                audio: true,
            });

            console.log(`${new Date().toISOString()}: Obtained stream with id: ${this.localStream.id}`);

            console.log(`${new Date().toISOString()}: Creating peer connection`);
            this.pc = new RTCPeerConnection({ iceServers: iceServers });

            // handle local events
            this.pc.onconnectionstatechange = () => {
                if (this.pc.connectionState === "connected") {
                    console.log(`${new Date().toISOString()}: peer connection connected, starting streaming`);
                } else if (this.pc.connectionState === "failed") {
                    console.log(`${new Date().toISOString()}: peer connection failed, restarting ICE`);
                    this.pc.restartIce();
                    // this.stopStreaming(this);
                }
            };

            this.pc.onicecandidate = (ev) => {
                console.log(`${new Date().toISOString()}: Sending ICE candidate`);
                this.pushEventTo(this.el, "ice", JSON.stringify(ev.candidate));
            };

            this.pc.ontrack = (event) => {
                console.log(`${new Date().toISOString()}: received track, creating audio element`);

                const trackId = event.track.id;
                const audioPlayer = document.createElement('audio');
                audioPlayer.srcObject = event.streams[0];
                audioPlayer.autoplay = true;
                audioPlayer.muted = false;

                this.audioPlayerWrapper.appendChild(audioPlayer);

                event.track.onended = (_) => {
                    console.log(`${new Date().toISOString()}: track ended: ${trackId}`);
                    this.audioPlayerWrapper.removeChild(audioPlayer);
                    this.pc?.getSenders().filter((sender) => sender.track?.id === trackId).forEach((sender) => {
                        this.pc.removeTrack(sender);
                    })
                }
            }

            console.log(`${new Date().toISOString()}: Adding track to peer connection`);
            // this.pc.addTrack(this.localStream.getAudioTracks()[0], this.localStream);
            this.pc.addTrack(this.createSineWaveTrack());

            console.log(`${new Date().toISOString()}: Creating offer`);
            const offer = await this.pc.createOffer();
            console.log(`${new Date().toISOString()}: Setting local description`);
            await this.pc.setLocalDescription(offer);

            console.log(`${new Date().toISOString()}: Sending offer`);
            this.pushEventTo(this.el, "offer", offer);
        },

        stopStreaming() {
            if (this.pc) {
                console.log(`${new Date().toISOString()}: Closing peer connection`);

                this.pc.close();
                this.pc = undefined;
            }

            if (this.localStream != undefined) {
                console.log(`${new Date().toISOString()}: Closing stream with id: ${this.localStream.id}`);
                this.localStream.getTracks().forEach((track) => track.stop());
                this.localStream = undefined;
            }
        },

        createSineWaveTrack(frequency = 196) { // in Hz
            const audioContext = new AudioContext();
            const destination = audioContext.createMediaStreamDestination();

            const oscillator = audioContext.createOscillator();
            oscillator.type = 'sine';
            oscillator.frequency.setValueAtTime(frequency, audioContext.currentTime);
            oscillator.start();

            const gain = audioContext.createGain();
            gain.gain.value = 0.05;

            oscillator.connect(gain);
            gain.connect(destination);

            return destination.stream.getAudioTracks()[0];
        }
    };
}