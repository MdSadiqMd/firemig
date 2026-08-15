defmodule FiremigCoordinator.Migrations do
  @moduledoc "Durable migration lifecycle and event store."

  import Ecto.Query

  alias FiremigCoordinator.Migrations.{Events, Store, Validation}

  alias FiremigCoordinator.{
    Error,
    Idempotency,
    Migration,
    MigrationEvent,
    MigrationRecovery,
    Repo
  }

  @terminal_phases ~w(DONE FAILED ROLLED_BACK ORPHANED_AMBIGUOUS)

  def start(sandbox_id, attrs, idempotency_key) do
    with :ok <- Validation.validate_idempotency_key(idempotency_key),
         {:ok, destination} <- Validation.fetch_destination(attrs) do
      request_hash = Idempotency.request_hash(%{sandbox_id: sandbox_id, request: attrs})

      sandbox_id
      |> Store.start(attrs, destination, idempotency_key, request_hash)
      |> Events.after_start()
    end
  end

  def get(sandbox_id, migration_id) do
    case Repo.get_by(Migration, id: migration_id, sandbox_id: sandbox_id) do
      nil -> {:error, Error.new(404, "MIGRATION_NOT_FOUND", "Migration not found")}
      migration -> {:ok, migration}
    end
  end

  def get(migration_id), do: Repo.get(Migration, migration_id)

  def nonterminal do
    Repo.all(from migration in Migration, where: migration.phase not in @terminal_phases)
  end

  def transition(migration_or_id, next_phase, attrs \\ %{}, detail \\ %{}) do
    migration_or_id
    |> migration_id()
    |> Store.transition(next_phase, attrs, detail)
    |> Events.after_event()
  end

  def issue_resume(migration_or_id) do
    migration_or_id
    |> migration_id()
    |> Store.issue_resume()
    |> Events.after_event()
  end

  def begin_rollback(migration_or_id, reason) do
    migration = Repo.get!(Migration, migration_id(migration_or_id))

    case MigrationRecovery.rollback_allowed?(migration) do
      true ->
        transition(migration, "ROLLING_BACK_SOURCE", Validation.error_attrs(reason), %{
          reason: inspect(reason)
        })

      false ->
        {:error, :rollback_after_resume_forbidden}
    end
  end

  def complete_cutover(migration_or_id) do
    migration_or_id
    |> migration_id()
    |> Store.complete_cutover()
    |> Events.after_event()
  end

  def events_after(migration_id, sequence) do
    Repo.all(
      from event in MigrationEvent,
        where: event.migration_id == ^migration_id and event.seq > ^sequence,
        order_by: event.seq
    )
  end

  def subscribe(migration_id),
    do: Phoenix.PubSub.subscribe(FiremigCoordinator.PubSub, Events.topic(migration_id))

  defp migration_id(%Migration{id: id}), do: id
  defp migration_id(id), do: id
end
