defmodule FiremigCoordinator.Sandboxes.Clients do
  @moduledoc false

  alias FiremigCoordinator.Error

  def worker, do: Application.fetch_env!(:firemig_coordinator, :worker_client)
  def proxy, do: Application.fetch_env!(:firemig_coordinator, :proxy_client)

  def upstream_error(code, reason) do
    Error.new(502, code, "Upstream control call failed",
      retryable: true,
      details: %{reason: inspect(reason)}
    )
  end
end
