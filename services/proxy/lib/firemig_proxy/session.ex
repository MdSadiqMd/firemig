defmodule FiremigProxy.Session do
  @moduledoc false

  use GenServer, restart: :temporary

  alias FiremigProxy.SequenceFilter
  alias FiremigProxy.Session.{Flow, Guest, Transport}
  alias FiremigProxy.SessionState

  defstruct [
    :sandbox_id,
    :client_socket,
    :internal_socket,
    :route_manager,
    :retry_timer,
    :domain,
    sequence_aware?: false,
    sequence_filter: SequenceFilter.new(),
    retry_attempt: 0,
    client_armed?: false
  ]

  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      restart: :temporary
    }
  end

  def start_link({handler_options, genserver_options}) do
    GenServer.start_link(__MODULE__, handler_options, genserver_options)
  end

  @impl true
  def init(handler_options) do
    Process.flag(:trap_exit, true)
    {:ok, %__MODULE__{sandbox_id: Keyword.fetch!(handler_options, :sandbox_id)}}
  end

  @impl true
  def handle_info(
        {:thousand_island_ready, raw_socket, handler_config, acceptor_span, _start_time},
        state
      ) do
    socket = ThousandIsland.Socket.new(raw_socket, handler_config, acceptor_span)

    case ThousandIsland.Socket.handshake(socket) do
      {:ok, socket} -> Flow.initialize_session(socket, state)
      {:error, reason} -> {:stop, {:handshake_failed, reason}, state}
    end
  end

  def handle_info({:tcp, raw_socket, data}, %{client_socket: %{socket: raw_socket}} = state) do
    Flow.handle_client_data(data, %{state | client_armed?: false})
  end

  def handle_info({:tcp_closed, raw_socket}, %{client_socket: %{socket: raw_socket}} = state) do
    {:stop, :normal, state}
  end

  def handle_info(
        {:tcp_error, raw_socket, reason},
        %{client_socket: %{socket: raw_socket}} = state
      ) do
    {:stop, {:client_error, reason}, state}
  end

  def handle_info({:tcp, socket, data}, %{internal_socket: socket} = state) do
    Guest.handle_guest_data(data, socket, state)
  end

  def handle_info({:tcp_closed, socket}, %{internal_socket: socket} = state) do
    Flow.handle_internal_eof(%{state | internal_socket: nil})
  end

  def handle_info({:tcp_error, socket, _reason}, %{internal_socket: socket} = state) do
    Flow.handle_internal_eof(%{state | internal_socket: nil})
  end

  def handle_info({:begin_cutover, epoch}, state) do
    domain = SessionState.begin_cutover(state.domain, epoch)
    state = Transport.close_internal(%{state | domain: domain})
    {_action, domain} = SessionState.internal_eof(state.domain)
    {:noreply, %{state | domain: domain}}
  end

  def handle_info({:route_endpoint, endpoint, epoch}, state) do
    case SessionState.update_endpoint(state.domain, endpoint, epoch) do
      {:ok, domain} ->
        state = state |> Transport.close_internal() |> Transport.cancel_retry()
        send(self(), :connect_internal)
        {:noreply, %{state | domain: domain, retry_attempt: 0}}

      {:error, :stale_epoch} ->
        {:noreply, state}
    end
  end

  def handle_info(:connect_internal, state) do
    state = %{state | retry_timer: nil}

    case Transport.connect(state.domain.endpoint) do
      {:ok, socket} -> Flow.internal_connected(socket, state)
      {:error, reason} -> Transport.schedule_retry(reason, state)
    end
  end

  def handle_info({:EXIT, _pid, :shutdown}, state), do: {:stop, :shutdown, state}
  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Transport.close_internal(state)
    Transport.close_client(state.client_socket)
    :ok
  end
end
