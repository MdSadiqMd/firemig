defmodule FiremigProxy.SequenceFilterTest do
  use ExUnit.Case, async: true

  alias FiremigProxy.SequenceFilter

  test "replayed sequence values are removed across chunk boundaries" do
    {first, acknowledgements, state} =
      SequenceFilter.feed(
        SequenceFilter.new(),
        ~s({"seq":1}\n{"seq":2}\n{"seq":3})
      )

    assert IO.iodata_to_binary(first) == ~s({"seq":1}\n{"seq":2}\n)
    assert acknowledgements == [1, 2]

    {second, acknowledgements, state} =
      SequenceFilter.feed(state, ~s(\n{"seq":1}\n{"seq":2}\n{"seq":3}\n{"seq":4}\n))

    assert IO.iodata_to_binary(second) == ~s({"seq":3}\n{"seq":4}\n)
    assert acknowledgements == [3, 1, 2, 3, 4]
    assert state.last_sequence == 4
  end

  test "non-sequenced newline protocols pass through unchanged" do
    {outbound, acknowledgements, _state} =
      SequenceFilter.feed(SequenceFilter.new(), "hello\nworld\n")

    assert IO.iodata_to_binary(outbound) == "hello\nworld\n"
    assert acknowledgements == []
  end
end
