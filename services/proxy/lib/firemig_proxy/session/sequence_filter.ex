defmodule FiremigProxy.SequenceFilter do
  @moduledoc false

  defstruct buffer: "", last_sequence: 0

  @type t :: %__MODULE__{buffer: binary(), last_sequence: non_neg_integer()}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec feed(t(), binary()) :: {iodata(), [non_neg_integer()], t()}
  def feed(%__MODULE__{} = state, data) do
    parts = String.split(state.buffer <> data, "\n")
    remainder = List.last(parts) || ""
    complete = Enum.drop(parts, -1)

    {outbound, acknowledgements, last_sequence} =
      Enum.reduce(complete, {[], [], state.last_sequence}, &filter_line/2)

    {
      Enum.reverse(outbound),
      Enum.reverse(acknowledgements),
      %{state | buffer: remainder, last_sequence: last_sequence}
    }
  end

  defp filter_line("", accumulator), do: accumulator

  defp filter_line(line, {outbound, acknowledgements, last_sequence}) do
    case Jason.decode(line) do
      {:ok, %{"seq" => sequence}} when is_integer(sequence) and sequence <= last_sequence ->
        {outbound, [sequence | acknowledgements], last_sequence}

      {:ok, %{"seq" => sequence}} when is_integer(sequence) ->
        {[[line, ?\n] | outbound], [sequence | acknowledgements], sequence}

      _other ->
        {[[line, ?\n] | outbound], acknowledgements, last_sequence}
    end
  end
end
