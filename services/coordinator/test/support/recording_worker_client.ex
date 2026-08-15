defmodule FiremigCoordinator.RecordingWorkerClient do
  @moduledoc false

  @behaviour FiremigCoordinator.WorkerClient

  @impl true
  def create_sandbox(_worker, _attrs), do: {:ok, %{"state" => "running"}}

  @impl true
  def run_command(_worker, _sandbox_id, _epoch, _attrs), do: {:ok, %{}}

  @impl true
  def write_file(_worker, _sandbox_id, _epoch, _attrs), do: {:ok, %{}}

  @impl true
  def expose_port(worker, sandbox_id, epoch, guest_port) do
    notify({:worker_expose_port, worker, sandbox_id, epoch, guest_port})
    {:ok, %{"proxyHost" => "#{worker}.internal", "proxyPort" => guest_port}}
  end

  @impl true
  def prepare_migration(worker, sandbox_id, epoch, attrs) do
    notify({:worker_prepare_migration, worker, sandbox_id, epoch, attrs})

    case attrs.stage do
      "reserve" -> {:ok, %{"dependenciesReady" => true}}
      "prestage" -> {:ok, %{"prestageReady" => true}}
    end
  end

  @impl true
  def probe(_worker, _sandbox_id, _epoch), do: {:ok, %{"verdict" => "IDLE"}}

  @impl true
  def precopy(_worker, _sandbox_id, _epoch, _attrs),
    do: {:ok, %{"bytesTotal" => 0, "bytesTransferred" => 0}}

  @impl true
  def pause(_worker, _sandbox_id, _epoch), do: :ok

  @impl true
  def snapshot(_worker, _sandbox_id, _epoch, attrs),
    do: {:ok, %{"manifest" => %{"migrationId" => attrs.migrationId}, "bytesTotal" => 0}}

  @impl true
  def transfer(_worker, _sandbox_id, _epoch, _attrs),
    do: {:ok, %{"bytesTotal" => 0, "bytesTransferred" => 0}}

  @impl true
  def load(_worker, _sandbox_id, _epoch, _attrs), do: :ok

  @impl true
  def resume(_worker, _sandbox_id, _epoch), do: :ok

  @impl true
  def verify(_worker, _sandbox_id, _epoch, _attrs), do: {:ok, %{}}

  @impl true
  def rollback(_worker, _sandbox_id, _epoch, _attrs), do: :ok

  @impl true
  def fence_and_cleanup(worker, sandbox_id, epoch, attrs) do
    notify({:worker_fence_and_cleanup, worker, sandbox_id, epoch, attrs})
    :ok
  end

  defp notify(message) do
    send(Application.fetch_env!(:firemig_coordinator, :contract_test_pid), message)
  end
end
