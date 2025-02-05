export function createPublisherHook(iceServers = []) {
    return {
        async mounted() {
            const view = this;

            // this.el.querySelectorAll("#frequency-buttons>button").forEach((button) => {
            //     button.addEventListener("click", () => {
            //         const frequency = parseInt(button.textContent);
            //         view.pc.getSenders()[0].replaceTrack(view.createSineWaveTrack(frequency));
            //     });
            // });

            view.toggleVoiceChatButton = document.getElementById("toggle-voice-chat");
            view.toggleVoiceChatButton.addEventListener("click", async () => {
                if (view.pc === undefined) {
                    await view.startStreaming(view);

                    view.el.dataset.streaming = "true";

                    view.toggleVoiceChatButton.classList.remove("bg-zinc-100", "hover:bg-zinc-200/80");
                    view.toggleVoiceChatButton.classList.add("bg-green-300", "hover:bg-green-400/80");
                } else {
                    view.stopStreaming(view);

                    view.el.dataset.streaming = "false";

                    view.toggleVoiceChatButton.classList.remove("bg-green-300", "hover:bg-green-400/80");
                    view.toggleVoiceChatButton.classList.add("bg-zinc-100", "hover:bg-zinc-200/80");
                }
            });

            // handle remote events
            view.handleEvent(`answer-${view.el.id}`, async (answer) => {
                if (view.pc) {
                    console.log(`${new Date().toISOString()}: Setting remote description`);
                    await view.pc.setRemoteDescription(answer);
                } else {
                    console.warn(`${new Date().toISOString()}: Received SDP cnswer but there is no PC. Ignoring.`);
                }
            });

            view.handleEvent(`ice-${view.el.id}`, async (cand) => {
                if (view.pc) {
                    console.log(`${new Date().toISOString()}: Adding ICE candidate`);
                    await view.pc.addIceCandidate(JSON.parse(cand));
                } else {
                    console.warn(`${new Date().toISOString()}: Received ICE candidate but there is no PC. Ignoring.`);
                }
            });
        },

        async startStreaming(view) {
            if (view.localStream != undefined) {
                view.stopStreaming(view);
            }

            console.log(`${new Date().toISOString()}: Setting up local stream`);
            view.localStream = await window.navigator.mediaDevices.getUserMedia({
                audio: true,
            });

            console.log(`${new Date().toISOString()}: Obtained stream with id: ${view.localStream.id}`);

            console.log(`${new Date().toISOString()}: Creating peer connection`);
            view.pc = new RTCPeerConnection({ iceServers: iceServers });

            // handle local events
            view.pc.onconnectionstatechange = () => {
                if (view.pc.connectionState === "connected") {
                    console.log(`${new Date().toISOString()}: peer connection connected, starting streaming`);
                } else if (view.pc.connectionState === "failed") {
                    console.log(`${new Date().toISOString()}: peer connection failed, restarting ICE`);
                    view.pc.restartIce();
                    // view.stopStreaming(view);
                }
            };

            view.pc.onicecandidate = (ev) => {
                console.log(`${new Date().toISOString()}: Sending ICE candidate`);
                view.pushEventTo(view.el, "ice", JSON.stringify(ev.candidate));
            };

            console.log(`${new Date().toISOString()}: Adding track to peer connection`);
            view.pc.addTrack(view.localStream.getAudioTracks()[0], view.localStream);
            // view.pc.addTrack(view.createSineWaveTrack());

            console.log(`${new Date().toISOString()}: Creating offer`);
            const offer = await view.pc.createOffer();
            console.log(`${new Date().toISOString()}: Setting local description`);
            await view.pc.setLocalDescription(offer);

            console.log(`${new Date().toISOString()}: Sending offer`);
            view.pushEventTo(view.el, "offer", offer);
        },

        stopStreaming(view) {
            if (view.pc) {
                console.log(`${new Date().toISOString()}: Closing peer connection`);

                view.pc.close();
                view.pc = undefined;
            }

            if (view.localStream != undefined) {
                console.log(`${new Date().toISOString()}: Closing stream with id: ${view.localStream.id}`);
                view.localStream.getTracks().forEach((track) => track.stop());
                view.localStream = undefined;
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