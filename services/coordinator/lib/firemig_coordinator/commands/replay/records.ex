defmodule FiremigCoordinator.CommandReplayer.Records do
  @moduledoc false

  alias FiremigCoordinator.QueuedCommand

  def filter(records, sandbox_id, pending_commands) do
    pending_by_id = Map.new(pending_commands, &{&1.command_id, &1})

    records
    |> Enum.filter(&matching?(&1, sandbox_id, pending_by_id))
    |> Enum.sort_by(& &1.offset)
    |> Enum.uniq_by(&field(&1.value, "commandId", :commandId))
  end

  def field(map, string_key, atom_key),
    do: Map.get(map, string_key) || Map.get(map, atom_key)

  defp matching?(%{offset: offset, value: value}, sandbox_id, pending_by_id)
       when is_integer(offset) and is_map(value) do
    command_id = field(value, "commandId", :commandId)

    case Map.get(pending_by_id, command_id) do
      %QueuedCommand{} = command ->
        field(value, "sandboxId", :sandboxId) == sandbox_id and
          field(value, "userId", :userId) == command.user_id and
          command.sandbox_id == sandbox_id

      nil ->
        false
    end
  end

  defp matching?(_record, _sandbox_id, _pending_by_id), do: false
end
