defmodule FiremigProxy.RoutePoolSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: FiremigProxy.RouteRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: FiremigProxy.RouteDynamicSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
