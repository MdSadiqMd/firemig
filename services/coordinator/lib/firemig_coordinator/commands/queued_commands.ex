defmodule FiremigCoordinator.QueuedCommands do
  @moduledoc "Durable queued command publishing and replay state."

  import Ecto.Query

  alias FiremigCoordinator.{QueuedCommand, Repo}

  @replayable_statuses ~w(publishing pending)

  def publish(attrs) do
    with {:ok, disposition, command} <- create_or_fetch(attrs),
         :ok <- ensure_same_command(command, attrs) do
      publish_for_disposition(disposition, command)
    end
  end

  def get(command_id), do: Repo.get(QueuedCommand, command_id)

  def resolve_existing(nil, _attrs), do: :new

  def resolve_existing(%QueuedCommand{} = command, attrs) do
    case ensure_same_command(command, attrs) do
      :ok -> {:ok, command}
      {:error, _reason} = error -> error
    end
  end

  def pending_for_sandbox(sandbox_id) do
    Repo.all(
      from command in QueuedCommand,
        where: command.sandbox_id == ^sandbox_id and command.status in ^@replayable_statuses,
        order_by: [asc: command.inserted_at]
    )
  end

  def mark_done(%QueuedCommand{} = command, result) do
    command
    |> QueuedCommand.status_changeset(%{status: "done", result: result, error: nil})
    |> Repo.update()
  end

  def mark_failed(%QueuedCommand{} = command, error) do
    command
    |> QueuedCommand.status_changeset(%{status: "failed", error: error, result: nil})
    |> Repo.update()
  end

  defp create_or_fetch(attrs) do
    Repo.transaction(
      fn ->
        case Repo.get(QueuedCommand, attrs.command_id) do
          nil -> insert(attrs)
          command -> {:existing, command}
        end
      end,
      mode: :immediate
    )
    |> case do
      {:ok, {disposition, command}} -> {:ok, disposition, command}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert(attrs) do
    case Repo.insert(QueuedCommand.create_changeset(%QueuedCommand{}, attrs)) do
      {:ok, command} -> {:new, command}
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp publish_for_disposition(:existing, %QueuedCommand{status: status} = command)
       when status in ~w(pending done failed),
       do: {:ok, command, :duplicate}

  defp publish_for_disposition(disposition, command)
       when disposition in [:new, :existing] do
    case command_queue().publish(queue_payload(command)) do
      {:ok, %{partition: partition, offset: offset}} ->
        command
        |> QueuedCommand.status_changeset(%{
          status: "pending",
          partition: partition,
          offset: offset
        })
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, updated, disposition}
          {:error, changeset} -> {:error, changeset}
        end

      {:error, reason} ->
        {:error, {:queue_unavailable, reason}}
    end
  end

  defp ensure_same_command(command, attrs) do
    same? =
      command.sandbox_id == attrs.sandbox_id and command.user_id == attrs.user_id and
        command.idempotency_key == attrs.idempotency_key and command.payload == attrs.payload

    case same? do
      true -> :ok
      false -> {:error, :command_id_conflict}
    end
  end

  defp queue_payload(command) do
    %{
      command_id: command.command_id,
      sandbox_id: command.sandbox_id,
      user_id: command.user_id,
      idempotency_key: command.idempotency_key,
      payload: command.payload
    }
  end

  defp command_queue, do: Application.fetch_env!(:firemig_coordinator, :command_queue)
end
