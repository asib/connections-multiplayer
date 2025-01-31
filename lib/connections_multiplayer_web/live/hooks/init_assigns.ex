defmodule ConnectionsMultiplayerWeb.Hooks.InitAssigns do
  import Phoenix.Component
  import Phoenix.LiveView

  @avatars [
    "Duck",
    "Rabbit",
    "Ifrit",
    "Ibex",
    "Turtle",
    "Leopard",
    "Gopher",
    "Ferret",
    "Beaver",
    "Chinchilla",
    "Auroch",
    "Dingo",
    "Kraken",
    "Rhino",
    "Python",
    "Cormorant",
    "Platypus",
    "Elephant",
    "Jackal",
    "Dolphin",
    "Capybara",
    "Camel",
    "Chupacabra",
    "Tiger",
    "Kangaroo",
    "Armadillo",
    "Sheep",
    "Panda",
    "Hippo",
    "Cheetah",
    "Manatee",
    "Raccoon",
    "Wombat",
    "Dinosaur",
    "Hyena",
    "Crow",
    "Orangutan",
    "Wolf",
    "Chameleon",
    "Shrew",
    "Penguin",
    "Nyan Cat",
    "Liger",
    "Quagga",
    "Squirrel",
    "Wolverine",
    "Axolotl",
    "Anteater",
    "Frog",
    "Narwhal",
    "Mink",
    "Chipmunk",
    "Buffalo",
    "Monkey",
    "Bat",
    "Giraffe",
    "Iguana",
    "Fox",
    "Coyote",
    "Moose",
    "Otter",
    "Grizzly",
    "Koala",
    "Alligator",
    "Pumpkin",
    "Llama",
    "Badger",
    "Walrus",
    "Skunk",
    "Lemur",
    "Hedgehog"
  ]

  @colours ~w(
    bg-slate-600
    bg-red-900
    bg-orange-700
    bg-amber-600
    bg-lime-600
    bg-green-800
    bg-teal-600
    bg-cyan-600
    bg-sky-700
    bg-blue-600
    bg-indigo-600
    bg-violet-700
    bg-purple-600
    bg-fuchsia-700
    bg-pink-500
    bg-rose-700
  )

  # These aren't actually used anywhere, but we need to
  # list them somewhere in the source code for Tailwind
  # to generate the CSS: https://elixirforum.com/t/using-generated-class-names-in-tailwind-under-phoenix-1-7/57995/2
  # border-slate-600
  # border-red-900
  # border-orange-700
  # border-amber-600
  # border-lime-600
  # border-green-800
  # border-teal-600
  # border-cyan-600
  # border-sky-700
  # border-blue-600
  # border-indigo-600
  # border-violet-700
  # border-purple-600
  # border-fuchsia-700
  # border-pink-500
  # border-rose-700

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign_new(:is_game_page?, fn -> false end)
      |> assign_new(:show_date_picker?, fn -> false end)
      |> assign_new(:publisher_id, fn -> "publisher_#{:rand.uniform(999_999_999_999)}" end)
      |> attach_hook(:save_request_path, :handle_params, &save_request_path/3)

    socket =
      if connected?(socket) do
        socket
        |> assign_new(:avatar, fn ->
          "#{Enum.random(@avatars)}-#{:rand.uniform(999_999_999_999)}"
        end)
        |> assign_new(:colour, fn -> Enum.random(@colours) end)
      else
        socket
      end

    {:cont, socket}
  end

  defp save_request_path(_params, url, socket),
    do: {:cont, assign(socket, :current_uri_path, URI.parse(url).path)}
end
