defmodule FiremigCoordinator.MigrationRunner.Cutover do
  @moduledoc false

  alias FiremigCoordinator.MigrationRunner.{Clients, Driver, Outcomes}
  alias FiremigCoordinator.Migrations

  def drive(%{phase: "SNAPSHOTTING"} = migration) do
    payload = %{migrationId: migration.id, destination: migration.destination_worker}

    case Clients.worker().snapshot(
           migration.source_worker,
           migration.sandbox_id,
           migration.epoch_before,
           payload
         ) do
      {:ok, result} ->
        attrs = %{
          snapshot_manifest: result["manifest"] || result,
          bytes_total: result["bytesTotal"] || migration.bytes_total
        }

        Driver.advance(migration, "TRANSFERRING", attrs)

      {:error, reason} ->
        Outcomes.handle_failure(migration, reason)
    end
  end

  def drive(%{phase: "TRANSFERRING"} = migration) do
    payload = %{
      migrationId: migration.id,
      source: migration.source_worker,
      manifest: migration.snapshot_manifest
    }

    case Clients.worker().transfer(
           migration.destination_worker,
           migration.sandbox_id,
           migration.epoch_after,
           payload
         ) do
      {:ok, result} -> Driver.advance(migration, "LOADING", Clients.transfer_attrs(result))
      {:error, reason} -> Outcomes.handle_failure(migration, reason)
    end
  end

  def drive(%{phase: "LOADING"} = migration) do
    payload = %{migrationId: migration.id, manifest: migration.snapshot_manifest, resumeVm: false}

    with :ok <-
           Clients.worker().load(
             migration.destination_worker,
             migration.sandbox_id,
             migration.epoch_after,
             payload
           ),
         {:ok, issued} <- Migrations.issue_resume(migration) do
      resume_destination(issued)
    else
      {:error, reason} -> Outcomes.handle_failure(migration, reason)
    end
  end

  def drive(%{phase: "RESUMING"} = migration),
    do: Outcomes.mark_orphan(migration, :resume_intent_reconciled_without_acknowledgement)

  defp resume_destination(migration) do
    case Clients.worker().resume(
           migration.destination_worker,
           migration.sandbox_id,
           migration.epoch_after
         ) do
      :ok -> Driver.advance(migration, "VERIFYING")
      {:error, reason} -> Outcomes.mark_orphan(migration, {:resume_ambiguous, reason})
    end
  end
end
