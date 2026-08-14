defmodule FiremigProxy.SessionIntegrationTest do
  use ExUnit.Case

  alias FiremigProxy.{RouteManager, Routes}

  test "the external socket survives guest EOF and carries buffered data to the new endpoint" do
    old_guest = start_guest(:old)
    new_guest = start_guest(:new)
    sandbox_id = "tcp-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Routes.delete(sandbox_id)
      :gen_tcp.close(old_guest.listener)
      :gen_tcp.close(new_guest.listener)
    end)

    assert {:ok, %{proxyPort: proxy_port}} =
             Routes.create(%{
               sandbox_id: sandbox_id,
               guest_port: 8080,
               preferred_proxy_port: nil,
               endpoint: %{host: "127.0.0.1", port: old_guest.port},
               epoch: 1
             })

    assert {:ok, client} =
             :gen_tcp.connect(~c"127.0.0.1", proxy_port, [:binary, active: false], 1_000)

    on_exit(fn -> :gen_tcp.close(client) end)

    assert_receive {:guest_connected, :old}, 1_000
    assert :ok = :gen_tcp.send(client, "before")
    assert {:ok, "old:before"} = :gen_tcp.recv(client, 0, 1_000)

    assert {:ok, %{phase: "cutover"}} = Routes.begin_cutover(sandbox_id)
    session = only_session(sandbox_id)
    assert :sys.get_state(session).domain.cutover?

    send(old_guest.pid, :close)
    assert_receive {:guest_closed, :old}, 1_000

    assert :ok = :gen_tcp.send(client, "during")

    assert {:ok, %{epoch: 2}} =
             Routes.update_endpoint(
               sandbox_id,
               %{host: "127.0.0.1", port: new_guest.port},
               2
             )

    assert_receive {:guest_connected, :new}, 1_000
    assert {:ok, "new:during"} = :gen_tcp.recv(client, 0, 1_000)
    assert :sys.get_state(session).domain.gap_measured?

    assert {:ok, %{phase: "active", lastCutoverGapMs: gap_ms}} = Routes.status(sandbox_id)
    assert is_integer(gap_ms)
  end

  defp start_guest(label) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_ip, port}} = :inet.sockname(listener)
    test_pid = self()

    pid =
      spawn_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        send(test_pid, {:guest_connected, label})
        {:ok, data} = :gen_tcp.recv(socket, 0, 1_000)
        :ok = :gen_tcp.send(socket, [Atom.to_string(label), ?:, data])
        await_guest_close(socket, test_pid, label)
      end)

    %{listener: listener, pid: pid, port: port}
  end

  defp await_guest_close(socket, test_pid, label) do
    receive do
      :close ->
        :gen_tcp.close(socket)
        send(test_pid, {:guest_closed, label})
    after
      5_000 -> :gen_tcp.close(socket)
    end
  end

  defp only_session(sandbox_id) do
    state = :sys.get_state(RouteManager.via(sandbox_id))
    [session] = MapSet.to_list(state.sessions)
    session
  end
end
