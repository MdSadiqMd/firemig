defmodule FiremigCoordinator.Sandboxes.Boot do
  @moduledoc false

  alias FiremigCoordinator.Repo
  alias FiremigCoordinator.Sandboxes.Clients

  def boot(sandbox, request_attrs) do
    payload = %{
      id: sandbox.id,
      epoch: sandbox.epoch,
      cpu: sandbox.cpu,
      memoryMb: sandbox.memory_mb,
      kernel: request_attrs["kernel"],
      rootfs: request_attrs["rootfs"],
      metadata: sandbox.metadata
    }

    case Clients.worker().create_sandbox(sandbox.worker, payload) do
      {:ok, result} -> mark_booted(sandbox, result)
      {:error, reason} -> mark_boot_failed(sandbox, reason)
    end
  end

  defp mark_booted(sandbox, result) do
    changes = %{
      state: Map.get(result, "state", "running"),
      boot_id: result["bootId"],
      booted_at: DateTime.utc_now()
    }

    case Repo.update(Ecto.Changeset.change(sandbox, changes)) do
      {:ok, updated} -> {:ok, updated}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp mark_boot_failed(sandbox, reason) do
    _ = Repo.update(Ecto.Changeset.change(sandbox, state: "failed"))
    {:error, Clients.upstream_error("WORKER_UNAVAILABLE", reason)}
  end
end
