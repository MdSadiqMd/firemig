defmodule FiremigCoordinator.Migrations.Store do
  @moduledoc false

  alias Ecto.Changeset
  alias FiremigCoordinator.Migrations.{Validation, Writer}
  alias FiremigCoordinator.{Migration, MigrationState, Repo, Sandbox}

  def start(sandbox_id, attrs, destination, key, request_hash) do
    Repo.transaction(
      fn -> Writer.create_or_replay(sandbox_id, attrs, destination, key, request_hash) end,
      mode: :immediate
    )
  end

  def transition(migration_id, next_phase, attrs, detail) do
    Repo.transaction(
      fn ->
        migration = Repo.get!(Migration, migration_id)

        case MigrationState.transition(migration.phase, next_phase) do
          :ok -> Writer.persist_transition(migration, next_phase, attrs, detail)
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      mode: :immediate
    )
  end

  def issue_resume(migration_id) do
    Repo.transaction(
      fn ->
        migration = Repo.get!(Migration, migration_id)

        with :ok <- MigrationState.transition(migration.phase, "RESUMING"),
             :ok <- Validation.ensure_unconsumed(migration) do
          persist_resume_intent(migration)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      mode: :immediate
    )
  end

  def complete_cutover(migration_id) do
    Repo.transaction(
      fn ->
        migration = Repo.get!(Migration, migration_id)

        case MigrationState.transition(migration.phase, "CLEANUP") do
          :ok -> transfer_ownership(migration)
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      mode: :immediate
    )
  end

  defp persist_resume_intent(migration) do
    updated =
      migration
      |> Migration.transition_changeset(%{
        phase: "RESUMING",
        snapshot_consumed: true,
        resume_issued_at: DateTime.utc_now()
      })
      |> Repo.update!()

    Sandbox
    |> Repo.get!(migration.sandbox_id)
    |> Changeset.change(epoch: migration.epoch_after, state: "resuming")
    |> Repo.update!()

    {updated, Writer.insert_event(updated, %{pointOfNoReturn: true})}
  end

  defp transfer_ownership(migration) do
    sandbox = Repo.get!(Sandbox, migration.sandbox_id)

    sandbox
    |> Changeset.change(
      worker: migration.destination_worker,
      region: migration.destination_worker,
      generation: sandbox.generation + 1,
      state: "running"
    )
    |> Repo.update!()

    Writer.persist_transition(migration, "CLEANUP", %{}, %{ownershipTransferred: true})
  end
end
