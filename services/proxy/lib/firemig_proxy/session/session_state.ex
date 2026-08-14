defmodule FiremigProxy.SessionState do
  @moduledoc false

  @enforce_keys [:endpoint, :epoch, :max_buffer_bytes]
  defstruct [
    :endpoint,
    :epoch,
    :max_buffer_bytes,
    mode: :connecting,
    cutover?: false,
    buffer: :queue.new(),
    buffered_bytes: 0,
    last_byte_out_at: nil,
    cutover_baseline_at: nil,
    awaiting_new_endpoint_data?: false,
    gap_measured?: false
  ]

  @type t :: %__MODULE__{}

  @spec begin_cutover(t(), integer(), integer()) :: t()
  def begin_cutover(state, epoch, now \\ System.monotonic_time(:millisecond))

  def begin_cutover(%__MODULE__{epoch: epoch} = state, epoch, now) do
    baseline = state.last_byte_out_at || now

    %{
      state
      | cutover?: true,
        cutover_baseline_at: baseline,
        awaiting_new_endpoint_data?: false,
        gap_measured?: false
    }
  end

  def begin_cutover(%__MODULE__{} = state, _stale_epoch, _now), do: state

  @spec update_endpoint(t(), map(), non_neg_integer(), integer()) ::
          {:ok, t()} | {:error, :stale_epoch}
  def update_endpoint(state, endpoint, new_epoch, now \\ System.monotonic_time(:millisecond))

  def update_endpoint(%__MODULE__{epoch: epoch}, _endpoint, new_epoch, _now)
      when new_epoch <= epoch,
      do: {:error, :stale_epoch}

  def update_endpoint(%__MODULE__{} = state, endpoint, new_epoch, now) do
    baseline = state.last_byte_out_at || state.cutover_baseline_at || now

    {:ok,
     %{
       state
       | endpoint: endpoint,
         epoch: new_epoch,
         mode: :connecting,
         cutover?: true,
         cutover_baseline_at: baseline,
         awaiting_new_endpoint_data?: true,
         gap_measured?: false
     }}
  end

  @spec connected(t()) :: t()
  def connected(%__MODULE__{} = state), do: %{state | mode: :connected}

  @spec internal_eof(t()) :: {:keep_client | :close_client, t()}
  def internal_eof(%__MODULE__{cutover?: true} = state) do
    {:keep_client, %{state | mode: :waiting_endpoint}}
  end

  def internal_eof(%__MODULE__{} = state), do: {:close_client, state}

  @spec buffer_client(t(), binary()) :: {:ok, t()} | {:backpressure, t()}
  def buffer_client(%__MODULE__{} = state, data) do
    new_size = state.buffered_bytes + byte_size(data)
    buffer_client(state, data, new_size <= state.max_buffer_bytes)
  end

  @spec drain_buffer(t()) :: {iodata(), t()}
  def drain_buffer(%__MODULE__{} = state) do
    {:queue.to_list(state.buffer), %{state | buffer: :queue.new(), buffered_bytes: 0}}
  end

  @spec note_guest_data(t(), integer()) :: {t(), non_neg_integer() | nil}
  def note_guest_data(
        %__MODULE__{awaiting_new_endpoint_data?: true, gap_measured?: false} = state,
        now
      ) do
    gap_ms = max(now - state.cutover_baseline_at, 0)

    {%{
       state
       | last_byte_out_at: now,
         cutover?: false,
         awaiting_new_endpoint_data?: false,
         gap_measured?: true
     }, gap_ms}
  end

  def note_guest_data(%__MODULE__{cutover?: true} = state, now) do
    {%{state | last_byte_out_at: now, cutover_baseline_at: now}, nil}
  end

  def note_guest_data(%__MODULE__{} = state, now) do
    {%{state | last_byte_out_at: now}, nil}
  end

  defp buffer_client(state, data, true) do
    {:ok,
     %{
       state
       | buffer: :queue.in(data, state.buffer),
         buffered_bytes: state.buffered_bytes + byte_size(data)
     }}
  end

  defp buffer_client(state, _data, false), do: {:backpressure, state}
end
