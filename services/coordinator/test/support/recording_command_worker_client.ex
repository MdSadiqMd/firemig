defmodule FiremigCoordinator.RecordingCommandWorkerClient do
  @moduledoc false

  @behaviour FiremigCoordinator.WorkerClient

  @impl true
  def create_sandbox(_worker, _attrs), do: {:ok, %{"state" => "running"}}

  @impl true
  def run_command(worker, sandbox_id, epoch, attrs) do
    send(test_pid(), {:run_command, worker, sandbox_id, epoch, attrs})
    {:ok, %{"exitCode" => 0, "output" => attrs["command"]}}
  end

  @impl true
  def write_file(_worker, _sandbox_id, _epoch, _attrs), do: {:ok, %{}}

  @impl true
  def expose_port(_worker, _sandbox_id, _epoch, guest_port),
    do: {:ok, %{"proxyHost" => "worker.internal", "proxyPort" => guest_port}}

  @impl true
  def prepare_migration(_worker, _sandbox_id, _epoch, %{stage: "reserve"}),
    do: {:ok, %{"dependenciesReady" => true}}

  def prepare_migration(_worker, _sandbox_id, _epoch, %{stage: "prestage"}),
    do: {:ok, %{"prestageReady" => true}}

  @impl true
  def probe(_worker, _sandbox_id, _epoch), do: {:ok, %{"verdict" => "IDLE"}}

  @impl true
  def precopy(_worker, _sandbox_id, _epoch, _attrs),
    do: {:ok, %{"bytesTotal" => 0, "bytesTransferred" => 0}}

  @impl true
  def pause(_worker, _sandbox_id, _epoch), do: :ok

  @impl true
  def snapshot(_worker, _sandbox_id, _epoch, _attrs),
    do: {:ok, %{"manifest" => %{}, "bytesTotal" => 0}}

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
  def fence_and_cleanup(_worker, _sandbox_id, _epoch, _attrs), do: :ok

  defp test_pid, do: Application.fetch_env!(:firemig_coordinator, :command_test_pid)
end
