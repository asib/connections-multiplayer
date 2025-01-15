defmodule ConnectionsMultiplayerWeb.Router do
  use ConnectionsMultiplayerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ConnectionsMultiplayerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", ConnectionsMultiplayerWeb do
    pipe_through :browser

    live "/", LobbyLive
    live "/:game_id", PlayLive
  end
end
