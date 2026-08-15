defmodule FiremigCoordinator.MigrationProcesses do
  @moduledoc false

  use Supervisor

  alias FiremigCoordinator.MigrationRunner

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  def start_runner(migration_id) do
    case DynamicSupervisor.start_child(
           FiremigCoordinator.MigrationRunnerSupervisor,
           {MigrationRunner, migration_id}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: FiremigCoordinator.MigrationRegistry},
      {DynamicSupervisor,
       strategy: :one_for_one, name: FiremigCoordinator.MigrationRunnerSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
