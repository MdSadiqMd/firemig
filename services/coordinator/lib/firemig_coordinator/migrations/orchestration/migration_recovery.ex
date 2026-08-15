defmodule FiremigCoordinator.MigrationRecovery do
  @moduledoc "Pure failure decisions around the destination resume boundary."

  alias FiremigCoordinator.MigrationState

  def failure_action(%{resume_issued_at: issued_at}) when not is_nil(issued_at), do: :orphan

  def failure_action(%{phase: phase}) do
    case MigrationState.rollback_phase?(phase) do
      true -> :rollback
      false -> :fail
    end
  end

  def rollback_allowed?(%{resume_issued_at: nil, phase: phase}),
    do: MigrationState.rollback_phase?(phase)

  def rollback_allowed?(_migration), do: false

  def reconcile_action(%{phase: "RESUMING", resume_issued_at: issued_at})
      when not is_nil(issued_at),
      do: :orphan

  def reconcile_action(_migration), do: :drive
end
