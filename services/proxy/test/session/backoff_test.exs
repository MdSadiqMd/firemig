defmodule FiremigProxy.BackoffTest do
  use ExUnit.Case, async: true

  alias FiremigProxy.Backoff

  test "retry delay is deterministic for supplied jitter and bounded" do
    assert Backoff.delay(0, 100, 1_000, 0) == 75
    assert Backoff.delay(1, 100, 1_000, 500) == 200
    assert Backoff.delay(20, 100, 1_000, 1_000) == 1_000
  end
end
