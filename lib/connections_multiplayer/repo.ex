defmodule ConnectionsMultiplayer.Repo do
  use Ecto.Repo,
    otp_app: :connections_multiplayer,
    adapter: Ecto.Adapters.SQLite3
end
