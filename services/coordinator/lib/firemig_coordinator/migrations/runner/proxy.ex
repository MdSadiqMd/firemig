defmodule FiremigCoordinator.MigrationRunner.Proxy do
  @moduledoc false

  alias FiremigCoordinator.MigrationRunner.Clients
  alias FiremigCoordinator.Sandboxes

  def begin_cutover(migration) do
    case Sandboxes.ports(migration.sandbox_id) do
      [] -> :ok
      [_port] -> Clients.proxy().begin_cutover(migration.sandbox_id)
    end
  end

  def repoint(migration) do
    case Sandboxes.ports(migration.sandbox_id) do
      [] -> :ok
      [port] -> repoint_exposed(migration, port)
    end
  end

  defp repoint_exposed(migration, port) do
    with {:ok, exposure} <-
           Clients.worker().expose_port(
             migration.destination_worker,
             migration.sandbox_id,
             migration.epoch_after,
             port.guest_port
           ),
         {:ok, endpoint} <- worker_endpoint(exposure) do
      Clients.proxy().repoint(migration.sandbox_id, endpoint, migration.epoch_after)
    end
  end

  defp worker_endpoint(%{"proxyHost" => host, "proxyPort" => port})
       when is_binary(host) and is_integer(port) and port in 1..65_535,
       do: {:ok, %{host: host, port: port}}

  defp worker_endpoint(exposure), do: {:error, {:invalid_worker_endpoint, exposure}}
end
