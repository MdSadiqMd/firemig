defmodule FiremigCoordinator.MigrationRunner.Driver do
  @moduledoc false

  alias FiremigCoordinator.MigrationRunner.{Cutover, Finalize, Outcomes, Prepare}
  alias FiremigCoordinator.Migrations

  @prepare_phases ~w(PREPARING RESERVING PRESTAGING PROBING PRECOPYING PAUSING)
  @cutover_phases ~w(SNAPSHOTTING TRANSFERRING LOADING RESUMING)
  @finalize_phases ~w(VERIFYING CUTOVER CLEANUP ROLLING_BACK_SOURCE)

  def drive(%{phase: phase} = migration) when phase in @prepare_phases,
    do: Prepare.drive(migration)

  def drive(%{phase: phase} = migration) when phase in @cutover_phases,
    do: Cutover.drive(migration)

  def drive(%{phase: phase} = migration) when phase in @finalize_phases,
    do: Finalize.drive(migration)

  def drive(_terminal_migration), do: :ok

  def advance(migration, next_phase, attrs \\ %{}, detail \\ %{}) do
    case Migrations.transition(migration, next_phase, attrs, detail) do
      {:ok, updated} -> drive(updated)
      {:error, reason} -> Outcomes.handle_failure(migration, reason)
    end
  end
end
