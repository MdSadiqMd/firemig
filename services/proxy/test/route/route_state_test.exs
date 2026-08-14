defmodule FiremigProxy.RouteStateTest do
  use ExUnit.Case, async: true

  alias FiremigProxy.RouteState

  setup do
    state =
      RouteState.new(%{
        sandbox_id: "sandbox-1",
        guest_port: 8080,
        endpoint: %{host: "old.internal", port: 8080},
        epoch: 3
      })

    %{state: state}
  end

  test "rejects stale endpoint epochs without changing state", %{state: state} do
    endpoint = %{host: "stale.internal", port: 8081}

    assert {:error, :stale_epoch} = RouteState.update_endpoint(state, endpoint, 3)
    assert state.endpoint.host == "old.internal"
    assert state.epoch == 3
  end

  test "transitions active through cutover and reconnecting back to active", %{state: state} do
    session = self()
    state = RouteState.register_session(state, session)

    assert {:ok, state} = RouteState.begin_cutover(state)
    assert state.phase == :cutover
    assert {:error, :invalid_transition} = RouteState.begin_cutover(state)

    endpoint = %{host: "new.internal", port: 8080}
    assert {:ok, state} = RouteState.update_endpoint(state, endpoint, 4)
    assert state.phase == :reconnecting
    assert MapSet.member?(state.pending_sessions, session)

    state = RouteState.session_connected(state, session, 4)
    assert state.phase == :active
    assert MapSet.size(state.pending_sessions) == 0
  end

  test "an endpoint update without sessions completes immediately", %{state: state} do
    assert {:ok, state} =
             RouteState.update_endpoint(state, %{host: "new.internal", port: 8080}, 4)

    assert state.phase == :active
    assert state.epoch == 4
  end
end
