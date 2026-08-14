defmodule FiremigProxy.SessionStateTest do
  use ExUnit.Case, async: true

  alias FiremigProxy.SessionState

  test "internal EOF during cutover preserves the external client" do
    state = %SessionState{
      endpoint: %{host: "127.0.0.1", port: 5000},
      epoch: 7,
      max_buffer_bytes: 16,
      mode: :connected
    }

    state = SessionState.begin_cutover(state, 7, 100)

    assert {:keep_client, state} = SessionState.internal_eof(state)
    assert state.mode == :waiting_endpoint
    assert state.cutover?
  end

  test "old endpoint output advances the gap baseline until the endpoint changes" do
    state = %SessionState{
      endpoint: %{host: "old", port: 5000},
      epoch: 1,
      max_buffer_bytes: 8,
      mode: :connected,
      last_byte_out_at: 90
    }

    state = SessionState.begin_cutover(state, 1, 100)
    {state, nil} = SessionState.note_guest_data(state, 110)
    assert state.cutover_baseline_at == 110

    assert {:ok, state} = SessionState.update_endpoint(state, %{host: "new", port: 5001}, 2, 120)
    {state, gap_ms} = SessionState.note_guest_data(state, 145)

    assert gap_ms == 35
    refute state.cutover?
    assert state.gap_measured?
  end

  test "client-to-guest buffer never exceeds its byte limit" do
    state = %SessionState{
      endpoint: %{host: "127.0.0.1", port: 5000},
      epoch: 1,
      max_buffer_bytes: 8
    }

    assert {:ok, state} = SessionState.buffer_client(state, "12345")
    assert state.buffered_bytes == 5
    assert {:backpressure, unchanged} = SessionState.buffer_client(state, "6789")
    assert unchanged.buffered_bytes == 5
    assert unchanged.buffered_bytes <= unchanged.max_buffer_bytes
  end
end
