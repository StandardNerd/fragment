defmodule FragmentWeb.Router do
  use FragmentWeb, :router

  pipeline :browser do
    plug :accepts, ["html", "text"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FragmentWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :browser_write_limit do
    plug FragmentWeb.Plugs.RateLimit, bucket: :browser_write
  end

  pipeline :api do
    plug :accepts, ["json", "text"]
  end

  pipeline :api_write_limit do
    plug FragmentWeb.Plugs.RateLimit, bucket: :api_write, format: :json
  end

  scope "/api", FragmentWeb.Api do
    pipe_through [:api, :api_write_limit]

    post "/pastes", PasteController, :create
    put "/pastes/:id", PasteController, :update
    patch "/pastes/:id", PasteController, :update
    delete "/pastes/:id", PasteController, :delete
  end

  scope "/api", FragmentWeb.Api do
    pipe_through :api

    get "/pastes/:id/raw", PasteController, :raw
    get "/pastes/:id", PasteController, :show
  end

  scope "/", FragmentWeb do
    pipe_through [:browser, :browser_write_limit]

    post "/pastes", PasteController, :create
    put "/pastes/:id", PasteController, :update
    patch "/pastes/:id", PasteController, :update
    delete "/pastes/:id", PasteController, :delete
    put "/:id", PasteController, :update
    patch "/:id", PasteController, :update
    delete "/:id", PasteController, :delete
  end

  scope "/", FragmentWeb do
    pipe_through :browser

    get "/", PasteController, :new
    get "/new", PasteController, :new
    get "/clone/:clone", PasteController, :new
    get "/api", PasteController, :api_docs
    get "/docs", PasteController, :api_docs

    get "/raw/:id", PasteController, :raw
    get "/pastes/:id/raw", PasteController, :raw
    get "/pastes/:id/edit", PasteController, :edit
    get "/pastes/:id", PasteController, :show

    get "/:id/edit", PasteController, :edit
    get "/:id", PasteController, :show
  end
end
