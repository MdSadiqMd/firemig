defmodule FiremigCoordinator.RoutingContractTest do
  use FiremigCoordinator.DataCase, async: false

  alias FiremigCoordinator.{Error, Migration, MigrationRunner, Port, Repo, Sandbox, Sandboxes}

  setup do
    previous_worker_client = Application.fetch_env!(:firemig_coordinator, :worker_client)
    previous_proxy_client = Application.fetch_env!(:firemig_coordinator, :proxy_client)
    previous_proxy_host = Application.fetch_env!(:firemig_coordinator, :proxy_public_host)

    Application.put_env(
      :firemig_coordinator,
      :worker_client,
      FiremigCoordinator.RecordingWorkerClient
    )

    Application.put_env(
      :firemig_coordinator,
      :proxy_client,
      FiremigCoordinator.RecordingProxyClient
    )

    Application.put_env(:firemig_coordinator, :proxy_public_host, "proxy.example.test")
    Application.put_env(:firemig_coordinator, :contract_test_pid, self())

    on_exit(fn ->
      Application.put_env(:firemig_coordinator, :worker_client, previous_worker_client)
      Application.put_env(:firemig_coordinator, :proxy_client, previous_proxy_client)
      Application.put_env(:firemig_coordinator, :proxy_public_host, previous_proxy_host)
      Application.delete_env(:firemig_coordinator, :contract_test_pid)
    end)

    :ok
  end

  test "initial exposure configures the worker endpoint before creating the proxy route" do
    sandbox = insert_sandbox(epoch: 3)

    assert {:ok, port, :created} =
             Sandboxes.expose_port(sandbox.id, %{"guestPort" => 8080})

    assert_receive {:worker_expose_port, "worker-a", sandbox_id, 3, 8080}
    assert sandbox_id == sandbox.id

    assert_receive {:proxy_expose_port, proxy_sandbox_id, attrs}
    assert proxy_sandbox_id == sandbox.id
    assert attrs.guestPort == 8080
    assert attrs.endpoint == %{host: "worker-a.internal", port: 8080}
    assert attrs.epoch == 3
    assert port.proxy_host == "proxy.example.test"
    assert port.proxy_port == 45_000
    assert port.url == "tcp://proxy.example.test:45000"

    assert {:ok, ^port, :replay} =
             Sandboxes.expose_port(sandbox.id, %{"guestPort" => 8080})

    assert {:error, %Error{status: 422, code: "ONE_PORT_PER_SANDBOX"}} =
             Sandboxes.expose_port(sandbox.id, %{"guestPort" => 9090})

    refute_receive {:worker_expose_port, _, _, _, _}
  end

  test "cutover configures the destination port and repoints to its returned endpoint" do
    sandbox = insert_sandbox(epoch: 1, state: "resuming")
    insert_port(sandbox.id, 8080)
    migration = insert_cutover_migration(sandbox)

    sandbox
    |> Ecto.Changeset.change(active_migration_id: migration.id)
    |> Repo.update!()

    pid = start_supervised!({MigrationRunner, migration.id})
    ref = Process.monitor(pid)

    assert_receive {:worker_expose_port, "worker-b", sandbox_id, 2, 8080}
    assert sandbox_id == sandbox.id

    assert_receive {:proxy_repoint, proxy_sandbox_id, endpoint, 2}
    assert proxy_sandbox_id == sandbox.id
    assert endpoint == %{host: "worker-b.internal", port: 8080}

    assert_receive {:worker_fence_and_cleanup, "worker-a", cleanup_sandbox_id, 2, _attrs}
    assert cleanup_sandbox_id == sandbox.id
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

    assert Repo.get!(Migration, migration.id).phase == "DONE"
    assert Repo.get!(Sandbox, sandbox.id).worker == "worker-b"
  end

  test "destination preparation carries the persisted guest port contract" do
    sandbox = insert_sandbox(epoch: 1, state: "migrating")
    insert_port(sandbox.id, 8080)
    migration = insert_reserving_migration(sandbox)

    sandbox
    |> Ecto.Changeset.change(active_migration_id: migration.id)
    |> Repo.update!()

    pid = start_supervised!({MigrationRunner, migration.id})
    ref = Process.monitor(pid)

    assert_receive {:worker_prepare_migration, "worker-b", sandbox_id, 2, attrs}
    assert sandbox_id == sandbox.id
    assert attrs.stage == "reserve"
    assert attrs.ports == [%{guestPort: 8080, protocol: "tcp"}]
    assert attrs.sandbox.id == sandbox.id
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert Repo.get!(Migration, migration.id).phase == "DONE"
  end

  defp insert_sandbox(options) do
    epoch = Keyword.fetch!(options, :epoch)
    state = Keyword.get(options, :state, "running")

    %Sandbox{}
    |> Sandbox.create_changeset(%{
      region: "worker-a",
      worker: "worker-a",
      cpu: 2,
      memory_mb: 1024
    })
    |> Ecto.Changeset.change(state: state, epoch: epoch)
    |> Repo.insert!()
  end

  defp insert_port(sandbox_id, guest_port) do
    %Port{sandbox_id: sandbox_id}
    |> Port.changeset(%{
      guest_port: guest_port,
      protocol: "tcp",
      proxy_host: "proxy.example.test",
      proxy_port: 45_000,
      url: "tcp://proxy.example.test:45000"
    })
    |> Repo.insert!()
  end

  defp insert_cutover_migration(sandbox) do
    %Migration{sandbox_id: sandbox.id}
    |> Migration.create_changeset(%{
      source_worker: "worker-a",
      destination_worker: "worker-b",
      idempotency_key: Ecto.UUID.generate(),
      request_hash: "routing-contract",
      epoch_before: 1,
      epoch_after: 2,
      options: %{}
    })
    |> Ecto.Changeset.change(
      phase: "CUTOVER",
      snapshot_consumed: true,
      resume_issued_at: DateTime.utc_now()
    )
    |> Repo.insert!()
  end

  defp insert_reserving_migration(sandbox) do
    %Migration{sandbox_id: sandbox.id}
    |> Migration.create_changeset(%{
      source_worker: "worker-a",
      destination_worker: "worker-b",
      idempotency_key: Ecto.UUID.generate(),
      request_hash: "prepare-contract",
      epoch_before: 1,
      epoch_after: 2,
      options: %{}
    })
    |> Ecto.Changeset.change(phase: "RESERVING")
    |> Repo.insert!()
  end
end
