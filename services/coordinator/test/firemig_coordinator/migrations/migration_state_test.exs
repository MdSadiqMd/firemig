defmodule FiremigCoordinator.MigrationStateTest do
  use ExUnit.Case, async: true

  alias FiremigCoordinator.MigrationState

  test "accepts every forward transition and rejects skipped or reversed phases" do
    forward_phases = ~w(
      PREPARING RESERVING PRESTAGING PROBING PRECOPYING PAUSING SNAPSHOTTING
      TRANSFERRING LOADING RESUMING VERIFYING CUTOVER CLEANUP DONE
    )

    forward_phases
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.each(fn [from, to] -> assert :ok = MigrationState.transition(from, to) end)

    assert {:error, {:invalid_transition, "PREPARING", "PAUSING"}} =
             MigrationState.transition("PREPARING", "PAUSING")

    assert {:error, {:invalid_transition, "VERIFYING", "RESUMING"}} =
             MigrationState.transition("VERIFYING", "RESUMING")
  end

  test "permits only phase-appropriate terminal recovery transitions" do
    assert :ok = MigrationState.transition("PREPARING", "FAILED")
    assert :ok = MigrationState.transition("LOADING", "ROLLING_BACK_SOURCE")
    assert :ok = MigrationState.transition("ROLLING_BACK_SOURCE", "ROLLED_BACK")
    assert :ok = MigrationState.transition("RESUMING", "ORPHANED_AMBIGUOUS")

    assert {:error, _reason} = MigrationState.transition("RESUMING", "ROLLING_BACK_SOURCE")
    assert {:error, _reason} = MigrationState.transition("LOADING", "ORPHANED_AMBIGUOUS")
    assert {:error, _reason} = MigrationState.transition("DONE", "PREPARING")
  end
end
