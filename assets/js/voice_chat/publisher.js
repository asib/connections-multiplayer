export function createPublisherHook(iceServers = []) {
    return {
        async mounted() {
            const view = this;

            view.audioDevices = [];

            view.toggleVoiceChatButton = document.getElementById("toggle-voice-chat");
            view.toggleVoiceChatButton.addEventListener("click", async () => {
                if (view.el.dataset.streaming === "false") {
                    await view.setupStream(view);
                    view.startStreaming(view);
                    view.el.dataset.streaming = "true";
                    view.toggleVoiceChatButton.classList.remove("bg-zinc-100", "hover:bg-zinc-200/80");
                    view.toggleVoiceChatButton.classList.add("bg-green-300", "hover:bg-green-400/80");
                    view.pushEvent("start-streaming", {});
                } else {
                    view.closeStream(view);
                    view.el.dataset.streaming = "false";
                    view.toggleVoiceChatButton.classList.remove("bg-green-300", "hover:bg-green-400/80");
                    view.toggleVoiceChatButton.classList.add("bg-zinc-100", "hover:bg-zinc-200/80");
                    view.pushEvent("stop-streaming", {});
                }
            });

            // handle remote events
            view.handleEvent(`answer-${view.el.id}`, async (answer) => {
                if (view.pc) {
                    await view.pc.setRemoteDescription(answer);
                } else {
                    console.warn("Received SDP cnswer but there is no PC. Ignoring.");
                }
            });

            view.handleEvent(`ice-${view.el.id}`, async (cand) => {
                if (view.pc) {
                    await view.pc.addIceCandidate(JSON.parse(cand));
                } else {
                    console.warn("Received ICE candidate but there is no PC. Ignoring.");
                }
            });

            // try {
            //     // skip device enumeration for now, go with default input
            //     await view.findDevices(view);
            //     try {
            //         await view.setupStream(view);
            //     } catch (error) {
            //         console.error("Couldn't setup stream, reason:", error.stack);
            //     }
            // } catch (error) {
            //     console.error(
            //         "Couldn't find audio and/or video devices, reason: ",
            //         error.stack
            //     );
            // }
        },

        // async findDevices(view) {
        //     // ask for permissions
        //     view.localStream = await navigator.mediaDevices.getUserMedia({ audio: true });

        //     console.log(`Obtained stream with id: ${view.localStream.id}`);

        //     // enumerate devices
        //     const devices = await navigator.mediaDevices.enumerateDevices();
        //     devices.forEach((device) => {
        //         if (device.kind === "audioinput") {
        //             // view.audioDevices.options[view.audioDevices.options.length] =
        //             //     new Option(device.label, device.deviceId);
        //             console.log(`audio device: ${device.label}`);
        //             view.audioDevices = view.audioDevices || [];
        //             view.audioDevices.push(device);
        //         }
        //     });

        //     // for some reasons, firefox loses labels after closing the stream
        //     // so we close it after filling audio/video devices selects
        //     view.closeStream(view);
        // },

        closeStream(view) {
            if (view.localStream != undefined) {
                console.log(`Closing stream with id: ${view.localStream.id}`);
                view.localStream.getTracks().forEach((track) => track.stop());
                view.localStream = undefined;
            }
        },

        async setupStream(view) {
            if (view.localStream != undefined) {
                view.closeStream(view);
            }

            view.localStream = await navigator.mediaDevices.getUserMedia({
                audio: true,
            });
            // view.localStream = await navigator.mediaDevices.getUserMedia({
            //     audio: {
            //         deviceId: { exact: view.audioDevices[0].deviceId },
            //         echoCancellation: true,
            //         autoGainControl: true,
            //         noiseSuppression: true,
            //     },
            // });

            console.log(`Obtained stream with id: ${view.localStream.id}`);
        },

        async startStreaming(view) {
            view.pc = new RTCPeerConnection({ iceServers: iceServers });

            // handle local events
            view.pc.onconnectionstatechange = () => {
                if (view.pc.connectionState === "connected") {
                    //
                } else if (view.pc.connectionState === "failed") {
                    view.pushEvent("stop-streaming", { reason: "failed" })
                    view.stopStreaming(view);
                }
            };

            view.pc.onicecandidate = (ev) => {
                view.pushEventTo(view.el, "ice", JSON.stringify(ev.candidate));
            };

            view.pc.addTrack(view.localStream.getAudioTracks()[0], view.localStream);

            const offer = await view.pc.createOffer();
            await view.pc.setLocalDescription(offer);

            view.pushEventTo(view.el, "offer", offer);
        },

        stopStreaming(view) {
            if (view.pc) {
                view.pc.close();
                view.pc = undefined;
            }
        }
    };
}