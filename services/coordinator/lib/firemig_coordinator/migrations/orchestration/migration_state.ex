defmodule FiremigCoordinator.MigrationState do
  @moduledoc "Pure migration phase transition rules."

  @normal_phases ~w(
    PREPARING RESERVING PRESTAGING PROBING PRECOPYING PAUSING SNAPSHOTTING
    TRANSFERRING LOADING RESUMING VERIFYING CUTOVER CLEANUP DONE
  )
  @terminal_phases ~w(DONE FAILED ROLLED_BACK ORPHANED_AMBIGUOUS)
  @rollback_phases ~w(PAUSING SNAPSHOTTING TRANSFERRING LOADING)

  @normal_transitions @normal_phases
                      |> Enum.chunk_every(2, 1, :discard)
                      |> Map.new(fn [from, to] -> {from, [to]} end)

  @prepause_transitions Map.new(
                          ~w(PREPARING RESERVING PRESTAGING PROBING PRECOPYING),
                          fn phase ->
                            {phase, ["FAILED" | Map.get(@normal_transitions, phase, [])]}
                          end
                        )
  @rollback_transitions Map.new(@rollback_phases, fn phase ->
                          {phase,
                           ["ROLLING_BACK_SOURCE" | Map.get(@normal_transitions, phase, [])]}
                        end)
  @post_resume_transitions Map.new(~w(RESUMING VERIFYING CUTOVER CLEANUP), fn phase ->
                             {phase,
                              ["ORPHANED_AMBIGUOUS" | Map.get(@normal_transitions, phase, [])]}
                           end)

  @transitions @normal_transitions
               |> Map.merge(@prepause_transitions)
               |> Map.merge(@rollback_transitions)
               |> Map.merge(@post_resume_transitions)
               |> Map.put("ROLLING_BACK_SOURCE", ["ROLLED_BACK", "FAILED"])

  def initial_phase, do: "PREPARING"
  def phases, do: @normal_phases ++ ~w(ROLLING_BACK_SOURCE FAILED ROLLED_BACK ORPHANED_AMBIGUOUS)
  def terminal?(phase), do: phase in @terminal_phases
  def active?(phase), do: not terminal?(phase)
  def rollback_phase?(phase), do: phase in @rollback_phases

  def transition(from, to) do
    case to in Map.get(@transitions, from, []) do
      true -> :ok
      false -> {:error, {:invalid_transition, from, to}}
    end
  end
end
