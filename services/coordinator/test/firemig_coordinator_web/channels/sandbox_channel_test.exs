defmodule FiremigCoordinatorWeb.SandboxChannelTest do
  use FiremigCoordinator.DataCase, async: false

  import Phoenix.ChannelTest

  alias FiremigCoordinator.{
    CommandReplayer,
    Migration,
    QueuedCommand,
    Repo,
    Sandbox
  }

  alias FiremigCoordinatorWeb.{SandboxChannel, UserSocket}

  @endpoint FiremigCoordinatorWeb.Endpoint

  setup do
    previous_worker_client = Application.fetch_env!(:firemig_coordinator, :worker_client)
    previous_api_token = Application.get_env(:firemig_coordinator, :api_token)

    Application.put_env(
      :firemig_coordinator,
      :worker_client,
      FiremigCoordinator.RecordingCommandWorkerClient
    )

    Application.put_env(:firemig_coordinator, :command_test_pid, self())
    Application.put_env(:firemig_coordinator, :api_token, nil)
    start_supervised!(FiremigCoordinator.MockCommandQueue)

    on_exit(fn ->
      Application.put_env(:firemig_coordinator, :worker_client, previous_worker_client)
      restore_env(:api_token, previous_api_token)
      Application.delete_env(:firemig_coordinator, :command_test_pid)
    end)

    :ok
  end

  test "socket requires userId and securely checks the optional API token" do
    Application.put_env(:firemig_coordinator, :api_token, "socket-secret")

    assert :error = UserSocket.connect(%{}, %Phoenix.Socket{}, %{})

    assert :error =
             UserSocket.connect(
               %{"userId" => "user-a", "token" => "wrong"},
               %Phoenix.Socket{},
               %{}
             )

    assert {:ok, socket} =
             UserSocket.connect(
               %{"userId" => "user-a", "token" => "socket-secret"},
               %Phoenix.Socket{},
               %{}
             )

    assert socket.assigns.user_id == "user-a"
  end

  test "join only permits the socket's user and an existing sandbox" do
    sandbox = insert_sandbox()

    assert {:ok, _reply, _socket} = join_channel(sandbox.id, "user-a")

    assert {:error, %{reason: "unauthorized"}} =
             socket(UserSocket, "user-a", %{user_id: "user-a"})
             |> subscribe_and_join(SandboxChannel, "sandbox:#{sandbox.id}:user-b")

    assert {:error, %{reason: "sandbox_not_found"}} =
             join_channel(Ecto.UUID.generate(), "user-a")
  end

  test "a running sandbox executes a WebSocket command directly" do
    sandbox = insert_sandbox()
    {:ok, _reply, socket} = join_channel(sandbox.id, "user-a")
    command = command_payload("direct-1", "echo direct")

    ref = push(socket, "command", command)

    assert_reply ref, :ok, %{
      "commandId" => "direct-1",
      "exitCode" => 0,
      "output" => "echo direct",
      "queued" => false
    }

    result = %{"exitCode" => 0, "output" => "echo direct"}

    assert_push "command_result", %{
      commandId: "direct-1",
      status: "done",
      result: ^result
    }

    assert_receive {:run_command, "worker-a", sandbox_id, 1, %{"command" => "echo direct"}}
    assert sandbox_id == sandbox.id
    refute Repo.get(QueuedCommand, "direct-1")
  end

  test "a migrating sandbox durably queues without executing" do
    sandbox = insert_sandbox(state: "migrating", active_migration_id: Ecto.UUID.generate())
    {:ok, _reply, socket} = join_channel(sandbox.id, "user-a")

    ref = push(socket, "command", command_payload("queued-1", "echo queued"))

    assert_reply ref, :ok, %{
      commandId: "queued-1",
      status: "queued",
      disposition: "new"
    }

    refute_receive {:run_command, _, _, _, _}
    command = Repo.get!(QueuedCommand, "queued-1")
    assert command.status == "pending"
    assert command.partition == 0
    assert command.offset == 0
  end

  test "duplicate commandId publishes once and returns the existing row" do
    sandbox = insert_sandbox(state: "migrating")
    {:ok, _reply, socket} = join_channel(sandbox.id, "user-a")
    command = command_payload("duplicate-1", "echo once")

    first_ref = push(socket, "command", command)
    assert_reply first_ref, :ok, %{status: "queued", disposition: "new"}

    second_ref = push(socket, "command", command)
    assert_reply second_ref, :ok, %{status: "queued", disposition: "duplicate"}

    assert length(FiremigCoordinator.MockCommandQueue.published()) == 1
    assert Repo.aggregate(QueuedCommand, :count) == 1
  end

  test "queue failure returns an error and leaves a publishing row for reconciliation" do
    sandbox = insert_sandbox(state: "migrating")
    {:ok, _reply, socket} = join_channel(sandbox.id, "user-a")
    FiremigCoordinator.MockCommandQueue.set_publish_result({:error, :unavailable})

    ref = push(socket, "command", command_payload("unavailable-1", "echo later"))

    assert_reply ref, :error, %{
      code: "COMMAND_QUEUE_UNAVAILABLE",
      message: "Command queue is unavailable",
      retryable: true
    }

    assert Repo.get!(QueuedCommand, "unavailable-1").status == "publishing"
    refute_receive {:run_command, _, _, _, _}
  end

  test "record filtering requires command, user, and sandbox matches and sorts by offset" do
    pending = [
      %QueuedCommand{command_id: "first", sandbox_id: "sandbox-a", user_id: "user-a"},
      %QueuedCommand{command_id: "second", sandbox_id: "sandbox-a", user_id: "user-a"}
    ]

    records = [
      record(8, "second", "user-a", "sandbox-a"),
      record(1, "first", "user-b", "sandbox-a"),
      record(3, "first", "user-a", "sandbox-b"),
      record(9, "done-or-direct", "user-a", "sandbox-a"),
      record(2, "first", "user-a", "sandbox-a")
    ]

    assert [first, second] = CommandReplayer.filter_records(records, "sandbox-a", pending)
    assert first.offset == 2
    assert second.offset == 8
  end

  test "DONE cleanup replays in offset order and isolates result broadcasts by user" do
    sandbox = insert_sandbox(state: "migrating", worker: "worker-b", epoch: 2)
    {:ok, _reply, user_a_socket} = join_channel(sandbox.id, "user-a")
    {:ok, _reply, _user_b_socket} = join_channel(sandbox.id, "user-b")

    second_ref = push(user_a_socket, "command", command_payload("second", "echo second"))
    assert_reply second_ref, :ok, %{status: "queued"}

    first_record = record(1, "first", "user-a", sandbox.id, %{"command" => "echo first"})
    [second_record] = FiremigCoordinator.MockCommandQueue.records() |> elem(1)

    FiremigCoordinator.MockCommandQueue.set_records([
      %{second_record | offset: 8},
      first_record
    ])

    first = insert_queued_command(sandbox.id, "first", "echo first", 1)
    assert first.status == "pending"

    migration = insert_cleanup_migration(sandbox)

    sandbox
    |> Ecto.Changeset.change(active_migration_id: migration.id)
    |> Repo.update!()

    pid = start_supervised!({FiremigCoordinator.MigrationRunner, migration.id})
    monitor = Process.monitor(pid)

    assert_receive {:run_command, "worker-b", sandbox_id, 2, %{"command" => "echo first"}}
    assert sandbox_id == sandbox.id
    assert_receive {:run_command, "worker-b", ^sandbox_id, 2, %{"command" => "echo second"}}

    assert_push "command_result", %{commandId: "first", status: "done"}
    assert_push "command_result", %{commandId: "second", status: "done"}
    refute_push "command_result", _payload
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}

    assert Repo.get!(Migration, migration.id).phase == "DONE"
    assert Repo.get!(QueuedCommand, "first").status == "done"
    assert Repo.get!(QueuedCommand, "second").status == "done"
  end

  test "command payload validation rejects missing identifiers and empty payloads" do
    sandbox = insert_sandbox()
    {:ok, _reply, socket} = join_channel(sandbox.id, "user-a")

    ref = push(socket, "command", %{"commandId" => "invalid", "payload" => %{}})

    assert_reply ref, :error, %{
      code: "VALIDATION_ERROR",
      message: "commandId, idempotencyKey, and payload are required"
    }
  end

  defp join_channel(sandbox_id, user_id) do
    socket(UserSocket, user_id, %{user_id: user_id})
    |> subscribe_and_join(SandboxChannel, "sandbox:#{sandbox_id}:#{user_id}")
  end

  defp command_payload(command_id, command) do
    %{
      "commandId" => command_id,
      "idempotencyKey" => "idempotency-#{command_id}",
      "payload" => %{"command" => command}
    }
  end

  defp insert_sandbox(options \\ []) do
    state = Keyword.get(options, :state, "running")
    worker = Keyword.get(options, :worker, "worker-a")

    %Sandbox{}
    |> Sandbox.create_changeset(%{
      region: worker,
      worker: worker,
      cpu: 2,
      memory_mb: 1024
    })
    |> Ecto.Changeset.change(
      state: state,
      worker: worker,
      region: worker,
      epoch: Keyword.get(options, :epoch, 1),
      active_migration_id: Keyword.get(options, :active_migration_id)
    )
    |> Repo.insert!()
  end

  defp insert_queued_command(sandbox_id, command_id, command, offset) do
    %QueuedCommand{}
    |> QueuedCommand.create_changeset(%{
      command_id: command_id,
      sandbox_id: sandbox_id,
      user_id: "user-a",
      idempotency_key: "idempotency-#{command_id}",
      payload: %{"command" => command}
    })
    |> QueuedCommand.status_changeset(%{status: "pending", partition: 0, offset: offset})
    |> Repo.insert!()
  end

  defp insert_cleanup_migration(sandbox) do
    %Migration{sandbox_id: sandbox.id}
    |> Migration.create_changeset(%{
      source_worker: "worker-a",
      destination_worker: "worker-b",
      idempotency_key: Ecto.UUID.generate(),
      request_hash: "command-replay",
      epoch_before: 1,
      epoch_after: 2,
      options: %{}
    })
    |> Ecto.Changeset.change(
      phase: "CLEANUP",
      snapshot_consumed: true,
      resume_issued_at: DateTime.utc_now()
    )
    |> Repo.insert!()
  end

  defp record(offset, command_id, user_id, sandbox_id, payload \\ %{"command" => "echo"}) do
    %{
      partition: 0,
      offset: offset,
      key: user_id,
      value: %{
        "commandId" => command_id,
        "userId" => user_id,
        "sandboxId" => sandbox_id,
        "idempotencyKey" => "idempotency-#{command_id}",
        "payload" => payload
      }
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:firemig_coordinator, key)
  defp restore_env(key, value), do: Application.put_env(:firemig_coordinator, key, value)
end
