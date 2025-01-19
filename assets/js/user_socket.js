// NOTE: The contents of this file will only be executed if
// you uncomment its entry in "assets/js/app.js".

// Bring in Phoenix channels client library:
import { Socket } from "phoenix"

let socket, channel;
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
    console.log("waiting for avatar or gameId", avatar, gameId)
    return;
  }

  socket = new Socket("/socket", { params: { avatar, colour } })

  // When you connect, you'll often need to authenticate the client.
  // For example, imagine you have an authentication plug, `MyAuth`,
  // which authenticates the session and assigns a `:current_user`.
  // If the current user exists you can assign the user's token in
  // the connection for use in the layout.
  //
  // In your "lib/connections_multiplayer_web/router.ex":
  //
  //     pipeline :browser do
  //       ...
  //       plug MyAuth
  //       plug :put_user_token
  //     end
  //
  //     defp put_user_token(conn, _) do
  //       if current_user = conn.assigns[:current_user] do
  //         token = Phoenix.Token.sign(conn, "user socket", current_user.id)
  //         assign(conn, :user_token, token)
  //       else
  //         conn
  //       end
  //     end
  //
  // Now you need to pass this token to JavaScript. You can do so
  // inside a script tag in "lib/connections_multiplayer_web/templates/layout/app.html.heex":
  //
  //     <script>window.userToken = "<%= assigns[:user_token] %>";</script>
  //
  // You will need to verify the user token in the "connect/3" function
  // in "lib/connections_multiplayer_web/channels/user_socket.ex":
  //
  //     def connect(%{"token" => token}, socket, _connect_info) do
  //       # max_age: 1209600 is equivalent to two weeks in seconds
  //       case Phoenix.Token.verify(socket, "user socket", token, max_age: 1_209_600) do
  //         {:ok, user_id} ->
  //           {:ok, assign(socket, :user, user_id)}
  //
  //         {:error, reason} ->
  //           :error
  //       end
  //     end
  //
  // Finally, connect to the socket:
  socket.connect()

  // Now that you are connected, you can join channels with a topic.
  // Let's assume you have a channel with a topic named `room` and the
  // subtopic is its id - in this case 42:
  let channel = socket.channel(`game:${gameId}:online_users`, {})
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

  if (socket !== undefined) {
    socket.disconnect(connectAndJoinChannel)
  } else {
    connectAndJoinChannel()
  }
}

setupSocket();

const mutationObserver = new MutationObserver((mutations) => {
  for (const _mutation of mutations) {
    console.log(`MutationObserver triggered: ${_mutation.target.value}`)
    setupSocket();
  }
});
mutationObserver.observe(document.querySelector("#user-avatar"), { attributes: true });

export { mutationObserver, setupSocket };
