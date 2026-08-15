defmodule FiremigCoordinator.CommandReplayer do
  @moduledoc "Replays migration-blocked commands against the sandbox's current owner."

  require Logger

  alias FiremigCoordinator.CommandReplayer.Records
  alias FiremigCoordinator.{Error, QueuedCommands, Sandboxes}
  alias FiremigCoordinatorWeb.Endpoint

  @task_supervisor FiremigCoordinator.CommandReplayer.TaskSupervisor

  def replay(sandbox_id) do
    sandbox_id
    |> QueuedCommands.pending_for_sandbox()
    |> start_replay_task(sandbox_id)
  end

  def replay_now(sandbox_id) do
    sandbox_id
    |> QueuedCommands.pending_for_sandbox()
    |> replay_pending(sandbox_id)
  end

  defdelegate filter_records(records, sandbox_id, pending_commands), to: Records, as: :filter

  defp replay_pending([], _sandbox_id), do: {:ok, []}

  defp replay_pending(pending_commands, sandbox_id) do
    with {:ok, records} <- command_queue().records() do
      records
      |> filter_records(sandbox_id, pending_commands)
      |> Enum.map(&replay_record(&1, pending_commands))
      |> then(&{:ok, &1})
    end
  end

  defp start_replay_task([], _sandbox_id), do: {:ok, nil}

  defp start_replay_task(pending_commands, sandbox_id) do
    Task.Supervisor.start_child(@task_supervisor, fn ->
      case replay_pending(pending_commands, sandbox_id) do
        {:ok, _commands} -> :ok
        {:error, reason} -> Logger.warning("command replay failed: #{inspect(reason)}")
      end
    end)
  end

  defp replay_record(record, pending_commands) do
    command_id = Records.field(record.value, "commandId", :commandId)
    command = Enum.find(pending_commands, &(&1.command_id == command_id))
    payload = Records.field(record.value, "payload", :payload)

    case Sandboxes.run_command(command.sandbox_id, payload) do
      {:ok, result} -> complete(command, result)
      {:error, reason} -> fail(command, reason)
    end
  end

  defp complete(command, result) do
    case QueuedCommands.mark_done(command, result) do
      {:ok, updated} ->
        broadcast(updated, %{commandId: updated.command_id, status: "done", result: result})
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp fail(command, reason) do
    error = error_payload(reason)

    case QueuedCommands.mark_failed(command, error) do
      {:ok, updated} ->
        broadcast(updated, %{commandId: updated.command_id, status: "failed", error: error})
        {:error, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp broadcast(command, payload) do
    Endpoint.broadcast(
      "sandbox:#{command.sandbox_id}:#{command.user_id}",
      "command_result",
      payload
    )
  end

  defp error_payload(%Error{} = error) do
    %{
      code: error.code,
      message: error.message,
      retryable: error.retryable,
      details: error.details
    }
  end

  defp error_payload(reason) do
    %{
      code: "COMMAND_FAILED",
      message: "Command execution failed",
      details: %{reason: inspect(reason)}
    }
  end

  defp command_queue, do: Application.fetch_env!(:firemig_coordinator, :command_queue)
end
