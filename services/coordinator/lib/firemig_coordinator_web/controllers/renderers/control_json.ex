defmodule FiremigCoordinatorWeb.ControlJSON do
  @moduledoc false

  alias FiremigCoordinator.{Migration, MigrationEvent, Port, Sandbox}

  def sandbox(%Sandbox{} = sandbox, ports, last_migration) do
    %{
      id: sandbox.id,
      state: sandbox.state,
      region: sandbox.region,
      worker: sandbox.worker,
      epoch: sandbox.epoch,
      generation: sandbox.generation,
      cpu: sandbox.cpu,
      memoryMb: sandbox.memory_mb,
      bootId: sandbox.boot_id,
      bootedAt: datetime(sandbox.booted_at),
      createdAt: datetime(sandbox.inserted_at),
      ports: Enum.map(ports, &port/1),
      activeMigrationId: sandbox.active_migration_id,
      lastMigration: optional_migration(last_migration)
    }
  end

  def migration(%Migration{} = migration) do
    %{
      migrationId: migration.id,
      sandboxId: migration.sandbox_id,
      phase: migration.phase,
      source: migration.source_worker,
      destination: migration.destination_worker,
      epochBefore: migration.epoch_before,
      epochAfter: migration.epoch_after,
      bytesTransferred: migration.bytes_transferred,
      bytesTotal: migration.bytes_total,
      path: migration.path_selected,
      snapshotConsumed: migration.snapshot_consumed,
      resumeIssuedAt: datetime(migration.resume_issued_at),
      error: migration_error(migration),
      createdAt: datetime(migration.inserted_at),
      updatedAt: datetime(migration.updated_at)
    }
  end

  def event(%MigrationEvent{} = event) do
    %{
      phase: event.phase,
      bytesTransferred: event.bytes,
      ts: datetime(event.inserted_at),
      details: event.detail
    }
  end

  def port(%Port{} = port) do
    %{
      guestPort: port.guest_port,
      protocol: port.protocol,
      proxyHost: port.proxy_host,
      proxyPort: port.proxy_port,
      url: port.url
    }
  end

  defp optional_migration(nil), do: nil
  defp optional_migration(migration), do: migration(migration)

  defp migration_error(%Migration{error_code: nil}), do: nil

  defp migration_error(%Migration{} = migration),
    do: %{code: migration.error_code, detail: migration.error_detail}

  defp datetime(nil), do: nil
  defp datetime(value), do: DateTime.to_iso8601(value)
end
