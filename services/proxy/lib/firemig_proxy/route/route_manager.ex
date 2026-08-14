defmodule FiremigProxy.RouteManager do
  @moduledoc false

  use GenServer

  alias FiremigProxy.RouteState

  def start_link(attrs) do
    GenServer.start_link(__MODULE__, attrs, name: via(attrs.sandbox_id))
  end

  def via(sandbox_id), do: {:via, Registry, {FiremigProxy.RouteRegistry, {:manager, sandbox_id}}}

  def register_session(sandbox_id, pid),
    do: GenServer.call(via(sandbox_id), {:register_session, pid})

  def begin_cutover(sandbox_id), do: GenServer.call(via(sandbox_id), :begin_cutover)

  def update_endpoint(sandbox_id, endpoint, epoch),
    do: GenServer.call(via(sandbox_id), {:update_endpoint, endpoint, epoch})

  def status(sandbox_id), do: GenServer.call(via(sandbox_id), :status)

  def set_proxy_port(sandbox_id, port),
    do: GenServer.call(via(sandbox_id), {:set_proxy_port, port})

  @impl true
  def init(attrs), do: {:ok, RouteState.new(attrs)}

  @impl true
  def handle_call({:register_session, pid}, _from, state) do
    Process.monitor(pid)
    state = RouteState.register_session(state, pid)

    reply = %{
      endpoint: state.endpoint,
      epoch: state.epoch,
      sequence_aware?: state.sequence_aware?,
      manager: self()
    }

    {:reply, {:ok, reply}, state}
  end

  def handle_call(:begin_cutover, _from, state) do
    case RouteState.begin_cutover(state) do
      {:ok, state} ->
        Enum.each(state.sessions, &send(&1, {:begin_cutover, state.epoch}))
        {:reply, {:ok, RouteState.status(state)}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:update_endpoint, endpoint, epoch}, _from, state) do
    case RouteState.update_endpoint(state, endpoint, epoch) do
      {:ok, state} ->
        Enum.each(state.sessions, &send(&1, {:route_endpoint, endpoint, epoch}))
        {:reply, {:ok, RouteState.status(state)}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:status, _from, state), do: {:reply, {:ok, RouteState.status(state)}, state}

  def handle_call({:set_proxy_port, port}, _from, state) do
    state = %{state | proxy_port: port}
    {:reply, {:ok, RouteState.status(state)}, state}
  end

  @impl true
  def handle_info({:session_connected, pid, epoch}, state) do
    {:noreply, RouteState.session_connected(state, pid, epoch)}
  end

  def handle_info({:cutover_gap, _pid, gap_ms}, state) do
    {:noreply, RouteState.record_gap(state, gap_ms)}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, RouteState.unregister_session(state, pid)}
  end
end
