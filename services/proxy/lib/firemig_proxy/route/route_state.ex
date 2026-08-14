defmodule FiremigProxy.RouteState do
  @moduledoc false

  @enforce_keys [:sandbox_id, :guest_port, :endpoint, :epoch]
  defstruct [
    :sandbox_id,
    :guest_port,
    :proxy_port,
    :endpoint,
    :epoch,
    sequence_aware?: false,
    phase: :active,
    sessions: MapSet.new(),
    pending_sessions: MapSet.new(),
    last_cutover_gap_ms: nil
  ]

  @type endpoint :: %{host: String.t(), port: :inet.port_number()}
  @type phase :: :active | :cutover | :reconnecting
  @type t :: %__MODULE__{}

  @spec new(map()) :: t()
  def new(attrs), do: struct!(__MODULE__, attrs)

  @spec begin_cutover(t()) :: {:ok, t()} | {:error, :invalid_transition}
  def begin_cutover(%__MODULE__{phase: :active} = state) do
    {:ok, %{state | phase: :cutover, last_cutover_gap_ms: nil}}
  end

  def begin_cutover(%__MODULE__{}), do: {:error, :invalid_transition}

  @spec update_endpoint(t(), endpoint(), non_neg_integer()) ::
          {:ok, t()} | {:error, :stale_epoch}
  def update_endpoint(%__MODULE__{epoch: epoch}, _endpoint, new_epoch) when new_epoch <= epoch do
    {:error, :stale_epoch}
  end

  def update_endpoint(%__MODULE__{} = state, endpoint, new_epoch) do
    pending_sessions = state.sessions
    phase = phase_for_pending(pending_sessions)

    {:ok,
     %{
       state
       | endpoint: endpoint,
         epoch: new_epoch,
         phase: phase,
         pending_sessions: pending_sessions
     }}
  end

  @spec register_session(t(), pid()) :: t()
  def register_session(%__MODULE__{phase: :reconnecting} = state, pid) do
    %{
      state
      | sessions: MapSet.put(state.sessions, pid),
        pending_sessions: MapSet.put(state.pending_sessions, pid)
    }
  end

  def register_session(%__MODULE__{} = state, pid) do
    %{state | sessions: MapSet.put(state.sessions, pid)}
  end

  @spec unregister_session(t(), pid()) :: t()
  def unregister_session(%__MODULE__{} = state, pid) do
    sessions = MapSet.delete(state.sessions, pid)
    pending_sessions = MapSet.delete(state.pending_sessions, pid)

    %{
      state
      | sessions: sessions,
        pending_sessions: pending_sessions,
        phase: completed_phase(state.phase, pending_sessions)
    }
  end

  @spec session_connected(t(), pid(), non_neg_integer()) :: t()
  def session_connected(%__MODULE__{phase: :reconnecting, epoch: epoch} = state, pid, epoch) do
    pending_sessions = MapSet.delete(state.pending_sessions, pid)
    %{state | pending_sessions: pending_sessions, phase: phase_for_pending(pending_sessions)}
  end

  def session_connected(%__MODULE__{} = state, _pid, _epoch), do: state

  @spec record_gap(t(), non_neg_integer()) :: t()
  def record_gap(%__MODULE__{last_cutover_gap_ms: nil} = state, gap_ms),
    do: %{state | last_cutover_gap_ms: gap_ms}

  def record_gap(%__MODULE__{} = state, gap_ms),
    do: %{state | last_cutover_gap_ms: max(state.last_cutover_gap_ms, gap_ms)}

  @spec status(t()) :: map()
  def status(%__MODULE__{} = state) do
    %{
      sandboxId: state.sandbox_id,
      guestPort: state.guest_port,
      proxyPort: state.proxy_port,
      endpoint: %{host: state.endpoint.host, port: state.endpoint.port},
      epoch: state.epoch,
      sequenceAware: state.sequence_aware?,
      phase: Atom.to_string(state.phase),
      sessionCount: MapSet.size(state.sessions),
      pendingSessionCount: MapSet.size(state.pending_sessions),
      lastCutoverGapMs: state.last_cutover_gap_ms
    }
  end

  defp completed_phase(:reconnecting, pending_sessions), do: phase_for_pending(pending_sessions)
  defp completed_phase(phase, _pending_sessions), do: phase

  defp phase_for_pending(pending_sessions) do
    case MapSet.size(pending_sessions) do
      0 -> :active
      _ -> :reconnecting
    end
  end
end
