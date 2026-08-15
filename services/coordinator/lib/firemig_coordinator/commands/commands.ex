defmodule FiremigCoordinator.Commands do
  @moduledoc "WebSocket sandbox command routing boundary."

  alias FiremigCoordinator.{CommandReplayer, QueuedCommand, QueuedCommands, Sandbox, Sandboxes}

  def submit(sandbox_id, user_id, attrs) do
    command_attrs = %{
      command_id: attrs.command_id,
      sandbox_id: sandbox_id,
      user_id: user_id,
      idempotency_key: attrs.idempotency_key,
      payload: attrs.payload
    }

    with {:ok, sandbox} <- Sandboxes.get(sandbox_id) do
      route(
        QueuedCommands.resolve_existing(QueuedCommands.get(attrs.command_id), command_attrs),
        sandbox,
        command_attrs
      )
    end
  end

  defp route({:ok, %QueuedCommand{status: "publishing"}}, sandbox, attrs) do
    case QueuedCommands.publish(attrs) do
      {:ok, command, disposition} ->
        maybe_replay(sandbox)
        {:ok, {:queued, command, disposition}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp route({:ok, %QueuedCommand{status: "pending"} = command}, sandbox, _attrs) do
    maybe_replay(sandbox)
    {:ok, {:queued, command, :duplicate}}
  end

  defp route({:ok, %QueuedCommand{} = command}, _sandbox, _attrs),
    do: {:ok, {:queued, command, :duplicate}}

  defp route({:error, _reason} = error, _sandbox, _attrs), do: error

  defp route(:new, %Sandbox{active_migration_id: nil, state: "running"} = sandbox, attrs) do
    case Sandboxes.run_command(sandbox.id, attrs.payload) do
      {:ok, result} -> {:ok, {:direct, attrs.command_id, result}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp route(:new, %Sandbox{}, attrs) do
    case QueuedCommands.publish(attrs) do
      {:ok, command, disposition} -> {:ok, {:queued, command, disposition}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_replay(%Sandbox{active_migration_id: nil, state: "running"} = sandbox) do
    _ = CommandReplayer.replay(sandbox.id)
    :ok
  end

  defp maybe_replay(%Sandbox{}), do: :ok
end
