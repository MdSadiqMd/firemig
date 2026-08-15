defmodule FiremigCoordinatorWeb.UserSocket do
  use Phoenix.Socket

  channel "sandbox:*", FiremigCoordinatorWeb.SandboxChannel

  @impl true
  def connect(%{"userId" => user_id} = params, socket, _connect_info)
      when is_binary(user_id) and byte_size(user_id) > 0 do
    case authorize(params["token"], Application.get_env(:firemig_coordinator, :api_token)) do
      :ok -> {:ok, assign(socket, :user_id, user_id)}
      :error -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"

  defp authorize(_presented, expected) when not is_binary(expected) or byte_size(expected) == 0,
    do: :ok

  defp authorize(presented, expected) when is_binary(presented) do
    case Plug.Crypto.secure_compare(digest(presented), digest(expected)) do
      true -> :ok
      false -> :error
    end
  end

  defp authorize(_presented, _expected), do: :error

  defp digest(token), do: :crypto.hash(:sha256, token)
end
