defmodule FiremigCoordinatorWeb.SandboxChannel do
  use FiremigCoordinatorWeb, :channel

  alias FiremigCoordinator.{Commands, Error, Sandboxes}
  alias FiremigCoordinatorWeb.Endpoint

  @impl true
  def join("sandbox:" <> identifiers, _payload, socket) do
    join_for_user(String.split(identifiers, ":", parts: 2), socket)
  end

  @impl true
  def handle_in("command", payload, socket) do
    with {:ok, attrs} <- validate_command(payload),
         {:ok, result} <-
           Commands.submit(socket.assigns.sandbox_id, socket.assigns.user_id, attrs) do
      reply_for_result(result, socket)
    else
      {:error, reason} -> {:reply, {:error, error_payload(reason)}, socket}
    end
  end

  defp join_for_user([sandbox_id, user_id], %{assigns: %{user_id: user_id}} = socket) do
    case Sandboxes.get(sandbox_id) do
      {:ok, _sandbox} -> {:ok, assign(socket, :sandbox_id, sandbox_id)}
      {:error, _reason} -> {:error, %{reason: "sandbox_not_found"}}
    end
  end

  defp join_for_user(_identifiers, _socket), do: {:error, %{reason: "unauthorized"}}

  defp validate_command(%{
         "commandId" => command_id,
         "idempotencyKey" => idempotency_key,
         "payload" => payload
       })
       when is_binary(command_id) and byte_size(command_id) > 0 and
              is_binary(idempotency_key) and byte_size(idempotency_key) > 0 and
              is_map(payload) and map_size(payload) > 0 do
    {:ok, %{command_id: command_id, idempotency_key: idempotency_key, payload: payload}}
  end

  defp validate_command(_payload), do: {:error, :invalid_command}

  defp reply_for_result({:direct, command_id, result}, socket) do
    payload = %{commandId: command_id, status: "done", result: result}
    Endpoint.broadcast(socket.topic, "command_result", payload)

    response =
      result
      |> Map.put_new("commandId", command_id)
      |> Map.put("queued", false)

    {:reply, {:ok, response}, socket}
  end

  defp reply_for_result({:queued, command, disposition}, socket) do
    status = command_reply_status(command.status)

    {:reply,
     {:ok,
      %{
        commandId: command.command_id,
        queued: true,
        status: status,
        disposition: Atom.to_string(disposition)
      }}, socket}
  end

  defp command_reply_status("publishing"), do: "publishing"
  defp command_reply_status("pending"), do: "queued"
  defp command_reply_status(status), do: status

  defp error_payload(%Error{} = error) do
    %{
      code: error.code,
      message: error.message,
      retryable: error.retryable,
      details: error.details
    }
  end

  defp error_payload(:invalid_command),
    do: %{
      code: "VALIDATION_ERROR",
      message: "commandId, idempotencyKey, and payload are required"
    }

  defp error_payload(:command_id_conflict),
    do: %{code: "COMMAND_ID_CONFLICT", message: "commandId was already used for another command"}

  defp error_payload({:queue_unavailable, _reason}),
    do: %{
      code: "COMMAND_QUEUE_UNAVAILABLE",
      message: "Command queue is unavailable",
      retryable: true
    }

  defp error_payload(reason),
    do: %{code: "COMMAND_FAILED", message: "Command failed", details: %{reason: inspect(reason)}}
end
