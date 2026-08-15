defmodule FiremigCoordinator.MigrationRecoveryTest do
  use FiremigCoordinator.DataCase, async: false

  alias FiremigCoordinator.{Migration, MigrationRecovery, Migrations, Repo, Sandbox}

  test "rollback is allowed before resume intent and forbidden afterward" do
    reversible = %{phase: "LOADING", resume_issued_at: nil}
    issued = %{phase: "RESUMING", resume_issued_at: DateTime.utc_now()}

    assert MigrationRecovery.rollback_allowed?(reversible)
    refute MigrationRecovery.rollback_allowed?(issued)
    assert :rollback = MigrationRecovery.failure_action(reversible)
    assert :orphan = MigrationRecovery.failure_action(issued)
  end

  test "resume boundary atomically consumes snapshot and advances ownership epoch" do
    sandbox = insert_sandbox()
    migration = insert_loading_migration(sandbox)

    assert {:ok, issued} = Migrations.issue_resume(migration)
    persisted_sandbox = Repo.get!(Sandbox, sandbox.id)

    assert issued.phase == "RESUMING"
    assert issued.snapshot_consumed
    assert issued.resume_issued_at
    assert persisted_sandbox.epoch == 8
    assert persisted_sandbox.state == "resuming"
    refute MigrationRecovery.rollback_allowed?(issued)
    assert :orphan = MigrationRecovery.reconcile_action(issued)
  end

  test "an issued resume cannot consume the snapshot twice" do
    sandbox = insert_sandbox()
    migration = insert_loading_migration(sandbox)

    assert {:ok, issued} = Migrations.issue_resume(migration)

    assert {:error, {:invalid_transition, "RESUMING", "RESUMING"}} =
             Migrations.issue_resume(issued)
  end

  defp insert_sandbox do
    %Sandbox{}
    |> Sandbox.create_changeset(%{
      region: "worker-a",
      worker: "worker-a",
      cpu: 2,
      memory_mb: 1024
    })
    |> Ecto.Changeset.change(state: "migrating", epoch: 7)
    |> Repo.insert!()
  end

  defp insert_loading_migration(sandbox) do
    %Migration{sandbox_id: sandbox.id}
    |> Migration.create_changeset(%{
      source_worker: "worker-a",
      destination_worker: "worker-b",
      idempotency_key: Ecto.UUID.generate(),
      request_hash: "hash",
      epoch_before: 7,
      epoch_after: 8,
      options: %{}
    })
    |> Ecto.Changeset.change(
      phase: "LOADING",
      snapshot_manifest: %{"artifacts" => []},
      snapshot_consumed: false
    )
    |> Repo.insert!()
  end
end
