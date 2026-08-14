defmodule FiremigProxy.Session.Flow do
  @moduledoc false

  alias FiremigProxy.RouteManager
  alias FiremigProxy.Session.Transport
  alias FiremigProxy.SessionState

  def initialize_session(socket, state) do
    case RouteManager.register_session(state.sandbox_id, self()) do
      {:ok, route} ->
        domain = %SessionState{
          endpoint: route.endpoint,
          epoch: route.epoch,
          max_buffer_bytes: Application.fetch_env!(:firemig_proxy, :buffer_bytes)
        }

        state = %{
          state
          | client_socket: socket,
            route_manager: route.manager,
            domain: domain,
            sequence_aware?: route.sequence_aware?
        }

        state = Transport.arm_client(state)
        send(self(), :connect_internal)
        {:noreply, state}

      {:error, reason} ->
        {:stop, reason, %{state | client_socket: socket}}
    end
  end

  def handle_client_data(data, %{internal_socket: socket, domain: %{mode: :connected}} = state) do
    case :gen_tcp.send(socket, data) do
      :ok -> {:noreply, Transport.arm_client(state)}
      {:error, _reason} -> buffer_after_send_failure(data, state)
    end
  end

  def handle_client_data(data, state) do
    case SessionState.buffer_client(state.domain, data) do
      {:ok, domain} -> {:noreply, %{state | domain: domain}}
      {:backpressure, domain} -> {:stop, :buffer_limit_exceeded, %{state | domain: domain}}
    end
  end

  def handle_internal_eof(state) do
    case SessionState.internal_eof(state.domain) do
      {:keep_client, domain} -> {:noreply, %{state | domain: domain}}
      {:close_client, domain} -> {:stop, :normal, %{state | domain: domain}}
    end
  end

  def internal_connected(socket, state) do
    :ok = :inet.setopts(socket, active: :once)
    connected_domain = SessionState.connected(state.domain)
    {buffer, drained_domain} = SessionState.drain_buffer(connected_domain)

    case Transport.send_buffer(socket, buffer) do
      :ok -> internal_ready(socket, drained_domain, state)
      {:error, reason} -> retry_after_buffer_failure(socket, connected_domain, reason, state)
    end
  end

  defp internal_ready(socket, drained_domain, state) do
    send(state.route_manager, {:session_connected, self(), drained_domain.epoch})

    state = %{
      state
      | internal_socket: socket,
        domain: drained_domain,
        retry_attempt: 0
    }

    {:noreply, Transport.arm_client(state)}
  end

  defp retry_after_buffer_failure(socket, connected_domain, reason, state) do
    :gen_tcp.close(socket)
    Transport.schedule_retry(reason, %{state | domain: %{connected_domain | mode: :connecting}})
  end

  defp buffer_after_send_failure(data, state) do
    state = Transport.close_internal(state)
    {_action, domain} = SessionState.internal_eof(%{state.domain | cutover?: true})

    case SessionState.buffer_client(domain, data) do
      {:ok, domain} ->
        send(self(), :connect_internal)
        {:noreply, %{state | domain: %{domain | mode: :connecting}}}

      {:backpressure, domain} ->
        {:stop, :buffer_limit_exceeded, %{state | domain: domain}}
    end
  end
end
