defmodule FiremigCoordinator.CommandQueue.RedpandaParser do
  @moduledoc false

  def publish_response(%{"offsets" => [offset | _]}), do: publish_offset(offset)
  def publish_response(body), do: {:error, {:invalid_publish_response, body}}

  def records(records) when is_list(records) do
    records
    |> Enum.reduce_while([], &record/2)
    |> case do
      {:error, _reason} = error -> error
      parsed -> {:ok, Enum.reverse(parsed)}
    end
  end

  def records(body), do: {:error, {:invalid_records_response, body}}

  defp publish_offset(%{"partition" => partition, "offset" => value, "error_code" => error_code})
       when is_integer(partition) and partition >= 0 and is_integer(value) and value >= 0 and
              error_code in [nil, 0],
       do: {:ok, %{partition: partition, offset: value}}

  defp publish_offset(%{"error_code" => _error_code} = error),
    do: {:error, {:publish_rejected, error}}

  defp publish_offset(%{"partition" => partition, "offset" => value})
       when is_integer(partition) and partition >= 0 and is_integer(value) and value >= 0,
       do: {:ok, %{partition: partition, offset: value}}

  defp publish_offset(error), do: {:error, {:publish_rejected, error}}

  defp record(
         %{"offset" => offset, "partition" => partition, "value" => value} = record,
         parsed
       )
       when is_integer(offset) and offset >= 0 and is_integer(partition) and partition >= 0 and
              is_map(value) do
    normalized = %{offset: offset, partition: partition, key: record["key"], value: value}
    {:cont, [normalized | parsed]}
  end

  defp record(record, _parsed), do: {:halt, {:error, {:invalid_record, record}}}
end
