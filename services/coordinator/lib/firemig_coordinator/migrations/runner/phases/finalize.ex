defmodule FiremigCoordinator.MigrationRunner.Finalize do
  @moduledoc false

  alias FiremigCoordinator.CommandReplayer
  alias FiremigCoordinator.MigrationRunner.{Clients, Driver, Outcomes, Proxy}
  alias FiremigCoordinator.Migrations

  def drive(%{phase: "VERIFYING"} = migration) do
    payload = %{migrationId: migration.id}

    case Clients.worker().verify(
           migration.destination_worker,
           migration.sandbox_id,
           migration.epoch_after,
           payload
         ) do
      {:ok, result} -> Driver.advance(migration, "CUTOVER", %{}, %{verification: result})
      {:error, reason} -> Outcomes.handle_failure(migration, reason)
    end
  end

  def drive(%{phase: "CUTOVER"} = migration) do
    case Proxy.repoint(migration) do
      :ok -> complete_cutover(migration)
      {:error, reason} -> Outcomes.handle_failure(migration, reason)
    end
  end

  def drive(%{phase: "CLEANUP"} = migration) do
    payload = %{migrationId: migration.id, destination: migration.destination_worker}

    case Clients.worker().fence_and_cleanup(
           migration.source_worker,
           migration.sandbox_id,
           migration.epoch_after,
           payload
         ) do
      :ok -> complete_cleanup(migration)
      {:error, reason} -> Outcomes.handle_failure(migration, reason)
    end
  end

  def drive(%{phase: "ROLLING_BACK_SOURCE"} = migration),
    do: Outcomes.execute_rollback(migration)

  defp complete_cutover(migration) do
    case Migrations.complete_cutover(migration) do
      {:ok, updated} -> Driver.drive(updated)
      {:error, reason} -> Outcomes.handle_failure(migration, reason)
    end
  end

  defp complete_cleanup(migration) do
    case Migrations.transition(migration, "DONE") do
      {:ok, completed} ->
        _ = CommandReplayer.replay(completed.sandbox_id)
        :ok

      {:error, reason} ->
        Outcomes.handle_failure(migration, reason)
    end
  end
end
