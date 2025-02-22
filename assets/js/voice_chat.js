export function createVoiceChatHook(iceServers = []) {
    return {
        async mounted() {
            this.audioPlayerWrapper = this.el.querySelector("#audio-player-wrapper");

            // this.el.querySelectorAll("#frequency-buttons>button").forEach((button) => {
            //     button.addEventListener("click", () => {
            //         const frequency = parseInt(button.textContent);
            //         this.pc.getSenders()[0].replaceTrack(this.createSineWaveTrack(frequency));
            //     });
            // });

            // this.muteMicrophoneButton = document.getElementById("mute-microphone");
            // this.muteMicrophoneButton.addEventListener("click", async () => {
            //     if (this.pc === undefined || this.microphoneSender?.track === undefined) {
            //         return;
            //     }

            //     this.microphoneSender.track.enabled = !this.microphoneSender.track.enabled;
            //     console.log(`${new Date().toISOString()}: microphone enabled: ${this.microphoneSender.track.enabled}`);

            //     if (this.microphoneSender.track.enabled) {
            //         this.muteMicrophoneButton.classList.remove("bg-red-800", "hover:bg-red-800/90");
            //         this.muteMicrophoneButton.classList.add("bg-gray-200", "hover:bg-gray-200/80");

            //         this.muteMicrophoneButton.querySelector("p").textContent = "Unmute microphone";
            //         this.muteMicrophoneButton.querySelector("p").classList.remove("text-white");

            //         this.muteMicrophoneButton.querySelector("#microphone").classList.add("stroke-black");
            //         this.muteMicrophoneButton.querySelector("#microphone").classList.remove("stroke-white");

            //         this.muteMicrophoneButton.querySelector("#mute-line-margin").classList.add("hidden");
            //         this.muteMicrophoneButton.querySelector("#mute-line").classList.add("hidden");
            //     } else {
            //         this.muteMicrophoneButton.classList.remove("bg-gray-200", "hover:bg-gray-200/80");
            //         this.muteMicrophoneButton.classList.add("bg-red-800", "hover:bg-red-800/90");

            //         this.muteMicrophoneButton.querySelector("p").textContent = "Mute microphone";
            //         this.muteMicrophoneButton.querySelector("p").classList.add("text-white");

            //         this.muteMicrophoneButton.querySelector("#microphone").classList.add("stroke-white");
            //         this.muteMicrophoneButton.querySelector("#microphone").classList.remove("stroke-black");

            //         this.muteMicrophoneButton.querySelector("#mute-line-margin").classList.remove("hidden");
            //         this.muteMicrophoneButton.querySelector("#mute-line").classList.remove("hidden");
            //     }

            //     this.pushEventTo(this.el, "toggle-mute-microphone", { enabled: this.microphoneSender.track.enabled });
            // });

            this.toggleVoiceChatButton = document.getElementById("toggle-voice-chat");
            this.toggleVoiceChatButton.addEventListener("click", async () => {
                if (this.pc === undefined) {
                    await this.startStreaming();

                    this.toggleVoiceChatButton.classList.remove("bg-blue-600", "sm:hover:bg-blue-600/90");
                    this.toggleVoiceChatButton.classList.add("bg-red-600", "sm:hover:bg-red-600/90");
                    this.toggleVoiceChatButton.querySelector("svg").classList.add("rotate-[135deg]", "translate-y-[2px]");
                    this.toggleVoiceChatButton.querySelector("p").textContent = "Leave voice chat";

                    // this.muteMicrophoneButton.classList.remove("hidden");
                    // this.muteMicrophoneButton.classList.add("inline-flex", "gap-2", "items-center", "sm:block");

                    this.pushEventTo(this.el, "toggle-voice-chat", { enabled: true });
                } else {
                    this.stopStreaming();

                    this.toggleVoiceChatButton.classList.remove("bg-red-600", "sm:hover:bg-red-600/90");
                    this.toggleVoiceChatButton.classList.add("bg-blue-600", "sm:hover:bg-blue-600/90");
                    this.toggleVoiceChatButton.querySelector("svg").classList.remove("rotate-[135deg]", "translate-y-[2px]");
                    this.toggleVoiceChatButton.querySelector("p").textContent = "Join voice chat";

                    // this.muteMicrophoneButton.classList.add("hidden");
                    // this.muteMicrophoneButton.classList.remove("inline-flex", "gap-2", "items-center", "sm:block");

                    this.pushEventTo(this.el, "toggle-voice-chat", { enabled: false });
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
            this.microphoneSender = this.pc.addTrack(this.localStream.getAudioTracks()[0], this.localStream);
            // this.microphoneSender = this.pc.addTrack(this.createSineWaveTrack());

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