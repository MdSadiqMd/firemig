defmodule FiremigCoordinator.MigrationRunner.Prepare do
  @moduledoc false

  alias FiremigCoordinator.MigrationRunner.{Clients, Driver, Outcomes, Proxy}
  alias FiremigCoordinator.{Sandbox, Sandboxes}

  def drive(%{phase: "PREPARING"} = migration),
    do: Driver.advance(migration, "RESERVING")

  def drive(%{phase: "RESERVING"} = migration) do
    with {:ok, sandbox} <- Sandboxes.get(migration.sandbox_id),
         {:ok, %{"dependenciesReady" => true}} <- prepare_stage(migration, sandbox, "reserve") do
      Driver.advance(migration, "PRESTAGING")
    else
      {:ok, result} ->
        Outcomes.handle_failure(migration, {:destination_dependencies_not_ready, result})

      {:error, reason} ->
        Outcomes.handle_failure(migration, reason)
    end
  end

  def drive(%{phase: "PRESTAGING"} = migration) do
    with {:ok, sandbox} <- Sandboxes.get(migration.sandbox_id),
         {:ok, %{"prestageReady" => true}} <- prepare_stage(migration, sandbox, "prestage") do
      Driver.advance(migration, "PROBING")
    else
      {:ok, result} ->
        Outcomes.handle_failure(migration, {:destination_prestage_not_ready, result})

      {:error, reason} ->
        Outcomes.handle_failure(migration, reason)
    end
  end

  def drive(%{phase: "PROBING"} = migration) do
    case Clients.worker().probe(
           migration.source_worker,
           migration.sandbox_id,
           migration.epoch_before
         ) do
      {:ok, result} ->
        path = result["path"] || result["verdict"] || "SAFE"
        Driver.advance(migration, "PRECOPYING", %{path_selected: path}, %{path: path})

      {:error, reason} ->
        Outcomes.handle_failure(migration, reason)
    end
  end

  def drive(%{phase: "PRECOPYING"} = migration) do
    payload = %{
      migrationId: migration.id,
      destination: migration.destination_worker,
      options: migration.options
    }

    case Clients.worker().precopy(
           migration.source_worker,
           migration.sandbox_id,
           migration.epoch_before,
           payload
         ) do
      {:ok, result} ->
        Driver.advance(migration, "PAUSING", Clients.transfer_attrs(result), %{precopy: result})

      {:error, reason} ->
        Outcomes.handle_failure(migration, reason)
    end
  end

  def drive(%{phase: "PAUSING"} = migration) do
    with :ok <- Proxy.begin_cutover(migration),
         :ok <-
           Clients.worker().pause(
             migration.source_worker,
             migration.sandbox_id,
             migration.epoch_before
           ) do
      Driver.advance(migration, "SNAPSHOTTING")
    else
      {:error, reason} -> Outcomes.handle_failure(migration, reason)
    end
  end

  defp prepare_stage(migration, sandbox, stage) do
    Clients.worker().prepare_migration(
      migration.destination_worker,
      migration.sandbox_id,
      migration.epoch_after,
      migration_payload(migration, sandbox, stage)
    )
  end

  defp migration_payload(migration, %Sandbox{} = sandbox, stage) do
    %{
      migrationId: migration.id,
      stage: stage,
      source: migration.source_worker,
      destination: migration.destination_worker,
      ports:
        Enum.map(Sandboxes.ports(sandbox.id), fn port ->
          %{guestPort: port.guest_port, protocol: port.protocol}
        end),
      sandbox: %{
        id: sandbox.id,
        cpu: sandbox.cpu,
        memoryMb: sandbox.memory_mb,
        bootId: sandbox.boot_id
      }
    }
  end
end
