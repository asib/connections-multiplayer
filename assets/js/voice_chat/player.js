export function createPlayerHook(iceServers = []) {
    return {
        async mounted() {
            console.log(`${new Date().toISOString()}: Creating peer connection`);
            this.pc = new RTCPeerConnection({ iceServers: iceServers });

            this.pc.onicecandidate = (ev) => {
                console.log(`${new Date().toISOString()}: Sending ICE candidate`);
                this.pushEventTo(this.el, "ice", JSON.stringify(ev.candidate));
            };

            this.pc.ontrack = (ev) => {
                console.log(`${new Date().toISOString()}: Receiving track`);
                if (!this.el.srcObject) {
                    console.log(`${new Date().toISOString()}: Setting srcObject`);
                    this.el.srcObject = ev.streams[0];
                }
            };
            this.pc.addTransceiver("audio", { direction: "recvonly" });

            const offer = await this.pc.createOffer();
            await this.pc.setLocalDescription(offer);

            const eventName = "answer" + "-" + this.el.id;
            this.handleEvent(eventName, async (answer) => {
                await this.pc.setRemoteDescription(answer);
            });

            this.pushEventTo(this.el, "offer", offer);
        },
    };
}