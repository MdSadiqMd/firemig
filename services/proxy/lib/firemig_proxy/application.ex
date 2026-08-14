defmodule FiremigProxy.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FiremigProxy.RoutePoolSupervisor,
      {Bandit,
       plug: FiremigProxy.AdminRouter,
       ip: Application.fetch_env!(:firemig_proxy, :admin_ip),
       port: Application.fetch_env!(:firemig_proxy, :admin_port),
       startup_log: false}
    ]

    opts = [strategy: :one_for_one, name: FiremigProxy.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
