defmodule FiremigCoordinator.Migrations.Writer do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Changeset
  alias FiremigCoordinator.Migrations.Validation
  alias FiremigCoordinator.{Idempotency, Migration, MigrationEvent, Repo, Sandbox}

  @terminal_phases ~w(DONE FAILED ROLLED_BACK ORPHANED_AMBIGUOUS)

  def create_or_replay(sandbox_id, attrs, destination, key, request_hash) do
    existing = Repo.get_by(Migration, idempotency_key: key)

    case Idempotency.resolve(existing, request_hash) do
      :new -> create_migration(sandbox_id, attrs, destination, key, request_hash)
      {:replay, migration} -> {:replay, migration, nil}
      {:error, :idempotency_key_conflict} -> Repo.rollback(Validation.idempotency_conflict())
    end
  end

  def persist_transition(migration, next_phase, attrs, detail) do
    updated =
      migration
      |> Migration.transition_changeset(Map.put(attrs, :phase, next_phase))
      |> Repo.update!()

    maybe_finalize_sandbox(updated)
    event = insert_event(updated, detail)
    {updated, event}
  end

  def insert_event(migration, detail) do
    next_sequence =
      Repo.one(
        from event in MigrationEvent,
          where: event.migration_id == ^migration.id,
          select: coalesce(max(event.seq), 0)
      ) + 1

    %MigrationEvent{migration_id: migration.id}
    |> MigrationEvent.changeset(%{
      seq: next_sequence,
      phase: migration.phase,
      bytes: migration.bytes_transferred,
      detail: detail
    })
    |> Repo.insert!()
  end

  defp create_migration(sandbox_id, attrs, destination, key, request_hash) do
    sandbox = Repo.get(Sandbox, sandbox_id) || Repo.rollback(Validation.sandbox_not_found())

    with :ok <- Validation.ensure_running(sandbox),
         :ok <- Validation.ensure_destination_changed(sandbox, destination),
         :ok <- Validation.ensure_no_active_migration(sandbox) do
      migration = insert_migration(sandbox, attrs, destination, key, request_hash)

      sandbox
      |> Changeset.change(active_migration_id: migration.id, state: "migrating")
      |> Repo.update!()

      event = insert_event(migration, %{source: sandbox.worker, destination: destination})
      {:created, migration, event}
    else
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp insert_migration(sandbox, attrs, destination, key, request_hash) do
    %Migration{sandbox_id: sandbox.id}
    |> Migration.create_changeset(%{
      source_worker: sandbox.worker,
      destination_worker: destination,
      idempotency_key: key,
      request_hash: request_hash,
      epoch_before: sandbox.epoch,
      epoch_after: sandbox.epoch + 1,
      options: Map.get(attrs, "options", %{})
    })
    |> Repo.insert!()
  end

  defp maybe_finalize_sandbox(%Migration{phase: phase} = migration)
       when phase in @terminal_phases do
    sandbox = Repo.get!(Sandbox, migration.sandbox_id)

    sandbox
    |> Changeset.change(active_migration_id: nil, state: terminal_sandbox_state(phase))
    |> Repo.update!()
  end

  defp maybe_finalize_sandbox(_migration), do: :ok

  defp terminal_sandbox_state("ORPHANED_AMBIGUOUS"), do: "orphaned_ambiguous"
  defp terminal_sandbox_state(_phase), do: "running"
end
