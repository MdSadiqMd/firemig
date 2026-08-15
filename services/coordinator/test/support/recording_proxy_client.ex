defmodule FiremigCoordinator.RecordingProxyClient do
  @moduledoc false

  @behaviour FiremigCoordinator.ProxyClient

  @impl true
  def expose_port(sandbox_id, attrs) do
    notify({:proxy_expose_port, sandbox_id, attrs})
    {:ok, %{"proxyPort" => 45_000}}
  end

  @impl true
  def begin_cutover(sandbox_id) do
    notify({:proxy_begin_cutover, sandbox_id})
    :ok
  end

  @impl true
  def repoint(sandbox_id, endpoint, epoch) do
    notify({:proxy_repoint, sandbox_id, endpoint, epoch})
    :ok
  end

  @impl true
  def status(sandbox_id) do
    notify({:proxy_status, sandbox_id})
    {:ok, %{"proxyPort" => 45_000}}
  end

  @impl true
  def delete(sandbox_id) do
    notify({:proxy_delete, sandbox_id})
    :ok
  end

  defp notify(message) do
    send(Application.fetch_env!(:firemig_coordinator, :contract_test_pid), message)
  end
end
