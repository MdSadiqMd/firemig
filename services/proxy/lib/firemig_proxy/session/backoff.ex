defmodule FiremigProxy.Backoff do
  @moduledoc false

  @spec delay(non_neg_integer(), pos_integer(), pos_integer(), 0..1000) :: pos_integer()
  def delay(attempt, base_ms, max_ms, jitter_unit)
      when attempt >= 0 and base_ms > 0 and max_ms >= base_ms and jitter_unit in 0..1000 do
    exponential = min(base_ms * Integer.pow(2, min(attempt, 30)), max_ms)
    jittered = div(exponential * (750 + div(jitter_unit, 2)), 1000)
    max(min(jittered, max_ms), 1)
  end
end
