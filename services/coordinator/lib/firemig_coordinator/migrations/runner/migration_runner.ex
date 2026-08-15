defmodule FiremigCoordinator.MigrationRunner do
  @moduledoc false

  use GenServer, restart: :transient

  alias FiremigCoordinator.MigrationRunner.{Driver, Outcomes}
  alias FiremigCoordinator.{MigrationRecovery, Migrations}

  def start_link(migration_id) do
    GenServer.start_link(__MODULE__, migration_id, name: via(migration_id))
  end

  def child_spec(migration_id) do
    %{
      id: {__MODULE__, migration_id},
      start: {__MODULE__, :start_link, [migration_id]},
      restart: :transient
    }
  end

  @impl true
  def init(migration_id), do: {:ok, migration_id, {:continue, :run}}

  @impl true
  def handle_continue(:run, migration_id) do
    migration_id |> Migrations.get() |> run_reconciled()
    {:stop, :normal, migration_id}
  end

  defp run_reconciled(nil), do: :ok

  defp run_reconciled(migration) do
    case MigrationRecovery.reconcile_action(migration) do
      :drive ->
        Driver.drive(migration)

      :orphan ->
        Outcomes.mark_orphan(migration, :coordinator_restarted_after_resume_intent)
    end
  end

  defp via(migration_id),
    do: {:via, Registry, {FiremigCoordinator.MigrationRegistry, migration_id}}
end
