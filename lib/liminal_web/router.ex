defmodule LiminalWeb.Router do
  use LiminalWeb, :router

  import LiminalWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LiminalWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Other scopes may use custom stacks.
  # scope "/api", LiminalWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:liminal, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LiminalWeb.Telemetry
    end
  end

  ## Authentication routes

  scope "/", LiminalWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/assets/:user_id/:filename", AssetController, :show
    get "/links/random", LinkController, :random

    live_session :require_authenticated_user,
      on_mount: [
        {LiminalWeb.UserAuth, :require_authenticated},
        {LiminalWeb.ExpiryPauseHooks, :default}
      ] do
      live "/users/settings", UserLive.Settings, :edit

      live "/", LinkLive.Index, :index
      live "/links/:id/edit", LinkLive.Index, :edit
      live "/tags", LinkLive.Index, :manage_tags
      live "/tags/new", LinkLive.Index, :new_tag
      live "/tags/:id/edit", LinkLive.Index, :edit_tag
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/admin", LiminalWeb.Admin do
    pipe_through [:browser, :require_authenticated_user, :require_admin_user]

    live_session :require_admin,
      on_mount: [
        {LiminalWeb.UserAuth, :require_admin},
        {LiminalWeb.ExpiryPauseHooks, :default}
      ] do
      live "/", DashboardLive, :index
      live "/users", UserLive.Index, :index
      live "/users/new", UserLive.Index, :new
    end
  end

  scope "/", LiminalWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [
        {LiminalWeb.UserAuth, :mount_current_scope},
        {LiminalWeb.ExpiryPauseHooks, :default}
      ] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/reset-password/:token", UserLive.ResetPassword, :edit
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
