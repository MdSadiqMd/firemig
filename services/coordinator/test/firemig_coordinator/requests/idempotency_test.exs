defmodule FiremigCoordinator.IdempotencyTest do
  use ExUnit.Case, async: true

  alias FiremigCoordinator.Idempotency

  test "canonical hash is independent of map insertion order" do
    first = %{"destination" => "worker-b", "options" => %{"precopyDisk" => true}}

    second =
      [{"options", %{"precopyDisk" => true}}, {"destination", "worker-b"}]
      |> Enum.into(%{})

    assert Idempotency.request_hash(first) == Idempotency.request_hash(second)
  end

  test "same key payload replays while a changed payload conflicts" do
    request_hash = Idempotency.request_hash(%{destination: "worker-b"})
    record = %{id: "migration-1", request_hash: request_hash}

    assert {:replay, ^record} = Idempotency.resolve(record, request_hash)
    assert {:error, :idempotency_key_conflict} = Idempotency.resolve(record, "different")
    assert :new = Idempotency.resolve(nil, request_hash)
  end
end
