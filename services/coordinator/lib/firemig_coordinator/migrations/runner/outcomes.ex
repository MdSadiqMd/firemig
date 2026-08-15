defmodule FiremigCoordinator.MigrationRunner.Outcomes do
  @moduledoc false

  require Logger

  alias FiremigCoordinator.MigrationRunner.Clients
  alias FiremigCoordinator.{MigrationRecovery, Migrations}

  def handle_failure(migration, reason) do
    current = Migrations.get(migration.id) || migration
    Logger.warning("migration #{migration.id} failed in #{current.phase}: #{inspect(reason)}")

    case MigrationRecovery.failure_action(current) do
      :fail -> mark_failed(current, reason)
      :rollback -> begin_and_execute_rollback(current, reason)
      :orphan -> mark_orphan(current, reason)
    end
  end

  def execute_rollback(migration) do
    payload = %{migrationId: migration.id, repairClock: true}

    case Clients.worker().rollback(
           migration.source_worker,
           migration.sandbox_id,
           migration.epoch_before,
           payload
         ) do
      :ok ->
        _ = Migrations.transition(migration, "ROLLED_BACK")
        :ok

      {:error, reason} ->
        _ =
          Migrations.transition(
            migration,
            "FAILED",
            failure_attrs("ROLLBACK_FAILED", reason),
            %{reason: inspect(reason)}
          )

        :ok
    end
  end

  def mark_failed(migration, reason) do
    _ =
      Migrations.transition(
        migration,
        "FAILED",
        failure_attrs("MIGRATION_STEP_FAILED", reason),
        %{reason: inspect(reason)}
      )

    :ok
  end

  def mark_orphan(migration, reason) do
    _ =
      Migrations.transition(
        migration,
        "ORPHANED_AMBIGUOUS",
        failure_attrs("RESUME_AMBIGUOUS", reason),
        %{reason: inspect(reason)}
      )

    :ok
  end

  defp begin_and_execute_rollback(migration, reason) do
    case Migrations.begin_rollback(migration, reason) do
      {:ok, rolling_back} -> execute_rollback(rolling_back)
      {:error, rollback_reason} -> mark_orphan(migration, rollback_reason)
    end
  end

  defp failure_attrs(code, reason),
    do: %{error_code: code, error_detail: inspect(reason)}
end
