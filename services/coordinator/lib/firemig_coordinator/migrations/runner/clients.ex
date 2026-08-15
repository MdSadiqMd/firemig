defmodule FiremigCoordinator.MigrationRunner.Clients do
  @moduledoc false

  def worker, do: Application.fetch_env!(:firemig_coordinator, :worker_client)
  def proxy, do: Application.fetch_env!(:firemig_coordinator, :proxy_client)

  def transfer_attrs(result) do
    %{
      bytes_total: result["bytesTotal"] || 0,
      bytes_transferred: result["bytesTransferred"] || 0
    }
  end
end
