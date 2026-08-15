defmodule FiremigCoordinator.CommandQueue do
  @moduledoc "Boundary for publishing and reading durable sandbox commands."

  @type command :: %{
          required(:command_id) => String.t(),
          required(:user_id) => String.t(),
          required(:sandbox_id) => String.t(),
          required(:idempotency_key) => String.t(),
          required(:payload) => map()
        }

  @type record :: %{
          required(:offset) => non_neg_integer(),
          required(:partition) => non_neg_integer(),
          optional(:key) => String.t() | nil,
          required(:value) => map()
        }

  @callback publish(command()) ::
              {:ok, %{partition: non_neg_integer(), offset: non_neg_integer()}}
              | {:error, term()}
  @callback records() :: {:ok, [record()]} | {:error, term()}
end
