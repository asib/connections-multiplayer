// NOTE: The contents of this file will only be executed if
// you uncomment its entry in "assets/js/app.js".

// Bring in Phoenix channels client library:
import { Socket } from "phoenix"

let socket = new Socket("/socket");
socket.connect();

let channel;
let avatar, colour, gameId;

function connectAndJoinChannel() {
  // And connect to the path in "lib/connections_multiplayer_web/endpoint.ex". We pass the
  // token for authentication. Read below how it should be used.
  avatar = document.querySelector("#user-avatar").value;
  colour = document.querySelector("#user-colour").value;
  gameId = window.location.pathname.split('/').pop();

  if (avatar === undefined
    || avatar === null
    || avatar === ""
    || gameId === undefined
    || gameId === null
    || gameId === "") {
    // We only set the avatar once the liveview socket has connected,
    // so if we're here before that happens, we don't have an avatar
    // with which to connect to the channel.
    // The mutation observer below will trigger when the avatar is set,
    // thereby triggering this function again with a defined avatar.
    return;
  }

  // Now that you are connected, you can join channels with a topic.
  // Let's assume you have a channel with a topic named `room` and the
  // subtopic is its id - in this case 42:
  let channel = socket.channel(`game:${gameId}:online_users`, { avatar, colour })
  channel.join()
    .receive("ok", resp => { console.log("Joined successfully", resp) })
    .receive("error", resp => { console.log("Unable to join", resp) })
}

function setupSocket() {
  if (avatar == document.querySelector("#user-avatar").value
    && colour == document.querySelector("#user-colour").value
    && gameId == window.location.pathname.split('/').pop()) {
    return;
  }

  if (channel !== undefined) channel.leave()

  connectAndJoinChannel()
}

const mutationObserver = new MutationObserver((mutations) => {
  for (const _mutation of mutations) {
    setupSocket();
  }
});
mutationObserver.observe(document.querySelector("#user-avatar"), { attributes: true });

export { mutationObserver, setupSocket };
