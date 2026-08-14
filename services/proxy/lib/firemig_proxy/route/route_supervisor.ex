defmodule FiremigProxy.RouteSupervisor do
  @moduledoc false

  use Supervisor

  alias FiremigProxy.{RouteManager, Session}

  def start_link(attrs) do
    Supervisor.start_link(__MODULE__, attrs,
      name: {:via, Registry, {FiremigProxy.RouteRegistry, {:supervisor, attrs.sandbox_id}}}
    )
  end

  @impl true
  def init(attrs) do
    listener_options = [
      port: attrs.preferred_proxy_port || 0,
      handler_module: Session,
      handler_options: [sandbox_id: attrs.sandbox_id],
      num_acceptors: Application.fetch_env!(:firemig_proxy, :num_acceptors),
      read_timeout: :infinity,
      transport_options: [
        ip: Application.fetch_env!(:firemig_proxy, :listener_ip),
        buffer: Application.fetch_env!(:firemig_proxy, :buffer_bytes),
        send_timeout: Application.fetch_env!(:firemig_proxy, :internal_send_timeout_ms),
        send_timeout_close: true
      ]
    ]

    listener = %{
      id: :listener,
      start: {ThousandIsland, :start_link, [listener_options]},
      type: :supervisor,
      shutdown: 15_000
    }

    Supervisor.init([{RouteManager, Map.drop(attrs, [:preferred_proxy_port])}, listener],
      strategy: :one_for_all
    )
  end

  def listener_port(supervisor) do
    with {:listener, listener, :supervisor, _modules} when is_pid(listener) <-
           List.keyfind(Supervisor.which_children(supervisor), :listener, 0),
         {:ok, {_ip, port}} <- ThousandIsland.listener_info(listener) do
      {:ok, port}
    else
      _ -> {:error, :listener_unavailable}
    end
  end
end
