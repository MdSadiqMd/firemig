defmodule FiremigCoordinator.Idempotency do
  @moduledoc "Canonical request hashing and replay validation."

  def request_hash(request) do
    request
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def resolve(nil, _request_hash), do: :new
  def resolve(%{request_hash: request_hash} = record, request_hash), do: {:replay, record}
  def resolve(_record, _request_hash), do: {:error, :idempotency_key_conflict}
end
