defmodule FiremigCoordinator.Sandboxes do
  @moduledoc "Public boundary for sandbox lifecycle and control operations."

  import Ecto.Query

  alias FiremigCoordinator.Sandboxes.{Boot, Clients, Exposure}
  alias FiremigCoordinator.{Error, Migration, Port, Repo, Sandbox}

  @barrier_phases ~w(
    PAUSING SNAPSHOTTING TRANSFERRING LOADING RESUMING VERIFYING CUTOVER CLEANUP
    ROLLING_BACK_SOURCE
  )

  def create(attrs) do
    create_attrs =
      attrs
      |> Map.put("worker", worker_for_region(attrs["region"]))
      |> Map.put("memory_mb", attrs["memoryMb"] || attrs["memory_mb"])

    case Repo.insert(Sandbox.create_changeset(%Sandbox{}, create_attrs)) do
      {:ok, sandbox} -> Boot.boot(sandbox, attrs)
      {:error, changeset} -> {:error, changeset}
    end
  end

  def get(id) do
    case Repo.get(Sandbox, id) do
      nil -> {:error, Error.new(404, "SANDBOX_NOT_FOUND", "Sandbox not found")}
      sandbox -> {:ok, sandbox}
    end
  end

  def ports(sandbox_id),
    do:
      Repo.all(
        from port in Port, where: port.sandbox_id == ^sandbox_id, order_by: port.guest_port
      )

  def last_migration(sandbox_id) do
    Repo.one(
      from migration in Migration,
        where: migration.sandbox_id == ^sandbox_id,
        order_by: [desc: migration.inserted_at],
        limit: 1
    )
  end

  def run_command(id, attrs) do
    with {:ok, sandbox} <- get(id),
         :ok <- ensure_mutable(sandbox),
         {:ok, result} <- Clients.worker().run_command(sandbox.worker, id, sandbox.epoch, attrs) do
      {:ok, result}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Clients.upstream_error("COMMAND_FAILED", reason)}
    end
  end

  def write_file(id, attrs) do
    with {:ok, sandbox} <- get(id),
         :ok <- ensure_mutable(sandbox),
         {:ok, result} <- Clients.worker().write_file(sandbox.worker, id, sandbox.epoch, attrs) do
      {:ok, result}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Clients.upstream_error("FILE_WRITE_FAILED", reason)}
    end
  end

  def expose_port(id, attrs) do
    with {:ok, sandbox} <- get(id),
         {:ok, guest_port} <- Exposure.validate_guest_port(attrs["guestPort"]),
         {:ok, disposition} <- Exposure.disposition(id, guest_port) do
      Exposure.expose(disposition, sandbox, attrs, guest_port)
    end
  end

  defp worker_for_region(region), do: region

  defp ensure_mutable(%Sandbox{active_migration_id: nil}), do: :ok

  defp ensure_mutable(%Sandbox{active_migration_id: migration_id}) do
    case Repo.get(Migration, migration_id) do
      %Migration{phase: phase} when phase in @barrier_phases ->
        {:error,
         Error.new(409, "MIGRATION_BARRIER", "Sandbox mutations are blocked during migration",
           details: %{migrationId: migration_id}
         )}

      %Migration{} ->
        :ok

      nil ->
        :ok
    end
  end
end
