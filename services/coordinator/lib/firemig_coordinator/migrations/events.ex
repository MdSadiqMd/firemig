defmodule FiremigCoordinator.Migrations.Events do
  @moduledoc false

  alias Ecto.Changeset
  alias FiremigCoordinator.{Error, MigrationProcesses}

  def after_start({:ok, {kind, migration, event}}) do
    maybe_broadcast(event)
    started(kind, migration)
  end

  def after_start({:error, %Error{} = error}), do: {:error, error}
  def after_start({:error, %Changeset{} = changeset}), do: {:error, changeset}
  def after_start({:error, reason}), do: {:error, reason}

  def after_event({:ok, {migration, event}}) do
    broadcast(event)
    {:ok, migration}
  end

  def after_event({:error, reason}), do: {:error, reason}

  def topic(migration_id), do: "migration:#{migration_id}"

  defp started(:created, migration) do
    _ = MigrationProcesses.start_runner(migration.id)
    {:ok, migration, :created}
  end

  defp started(:replay, migration), do: {:ok, migration, :replay}

  defp maybe_broadcast(nil), do: :ok
  defp maybe_broadcast(event), do: broadcast(event)

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(
      FiremigCoordinator.PubSub,
      topic(event.migration_id),
      {:migration_event, event}
    )
  end
end
