defmodule FiremigCoordinator.MockCommandQueue do
  @moduledoc false

  use Agent

  @behaviour FiremigCoordinator.CommandQueue

  def start_link(options \\ []) do
    Agent.start_link(fn -> initial_state(options) end, name: __MODULE__)
  end

  def set_publish_result(result), do: Agent.update(__MODULE__, &%{&1 | publish_result: result})
  def set_records(records), do: Agent.update(__MODULE__, &%{&1 | records: records})
  def published, do: Agent.get(__MODULE__, &Enum.reverse(&1.published))

  @impl true
  def publish(command) do
    Agent.get_and_update(__MODULE__, fn state ->
      case state.publish_result do
        :ok ->
          offset = state.next_offset
          record = kafka_record(command, offset)
          result = {:ok, %{partition: 0, offset: offset}}

          {result,
           %{
             state
             | next_offset: offset + 1,
               published: [command | state.published],
               records: [record | state.records]
           }}

        {:error, _reason} = error ->
          {error, %{state | published: [command | state.published]}}
      end
    end)
  end

  @impl true
  def records, do: Agent.get(__MODULE__, &{:ok, Enum.reverse(&1.records)})

  defp initial_state(options) do
    %{
      publish_result: Keyword.get(options, :publish_result, :ok),
      published: [],
      records: Keyword.get(options, :records, []),
      next_offset: Keyword.get(options, :next_offset, 0)
    }
  end

  defp kafka_record(command, offset) do
    %{
      partition: 0,
      offset: offset,
      key: command.user_id,
      value: %{
        "commandId" => command.command_id,
        "userId" => command.user_id,
        "sandboxId" => command.sandbox_id,
        "idempotencyKey" => command.idempotency_key,
        "payload" => command.payload
      }
    }
  end
end
