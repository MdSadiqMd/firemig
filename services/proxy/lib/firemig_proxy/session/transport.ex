defmodule FiremigProxy.Session.Transport do
  @moduledoc false

  alias FiremigProxy.Backoff

  require Logger

  def connect(%{host: host, port: port}) do
    timeout = Application.fetch_env!(:firemig_proxy, :connect_timeout_ms)
    send_timeout = Application.fetch_env!(:firemig_proxy, :internal_send_timeout_ms)

    options = [
      :binary,
      packet: :raw,
      active: false,
      nodelay: true,
      send_timeout: send_timeout,
      send_timeout_close: true
    ]

    :gen_tcp.connect(String.to_charlist(host), port, options, timeout)
  end

  def send_buffer(_socket, []), do: :ok
  def send_buffer(socket, buffer), do: :gen_tcp.send(socket, buffer)

  def send_client_data(_socket, []), do: :ok
  def send_client_data(socket, data), do: ThousandIsland.Socket.send(socket, data)

  def send_acknowledgements(_socket, []), do: :ok

  def send_acknowledgements(socket, acknowledgements) do
    payload = Enum.map(acknowledgements, &["ACK ", Integer.to_string(&1), ?\n])
    :gen_tcp.send(socket, payload)
  end

  def schedule_retry(reason, state) do
    base_ms = Application.fetch_env!(:firemig_proxy, :retry_base_ms)
    max_ms = Application.fetch_env!(:firemig_proxy, :retry_max_ms)
    jitter = :rand.uniform(1001) - 1
    delay = Backoff.delay(state.retry_attempt, base_ms, max_ms, jitter)
    timer = Process.send_after(self(), :connect_internal, delay)

    Logger.debug(
      "guest reconnect failed for #{state.sandbox_id}: #{inspect(reason)}; retrying in #{delay}ms"
    )

    {:noreply,
     %{
       state
       | retry_timer: timer,
         retry_attempt: state.retry_attempt + 1,
         internal_socket: nil
     }}
  end

  def arm_client(%{client_armed?: false} = state) do
    :ok = ThousandIsland.Socket.setopts(state.client_socket, active: :once)
    %{state | client_armed?: true}
  end

  def arm_client(state), do: state

  def close_internal(%{internal_socket: nil} = state), do: state

  def close_internal(%{internal_socket: socket} = state) do
    :gen_tcp.close(socket)
    %{state | internal_socket: nil}
  end

  def close_client(%ThousandIsland.Socket{} = socket), do: ThousandIsland.Socket.close(socket)
  def close_client(nil), do: :ok

  def cancel_retry(%{retry_timer: nil} = state), do: state

  def cancel_retry(%{retry_timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | retry_timer: nil}
  end
end
