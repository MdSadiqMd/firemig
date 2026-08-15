defmodule FiremigCoordinator.Error do
  @moduledoc false

  @enforce_keys [:status, :code, :message]
  defstruct [:status, :code, :message, retryable: false, details: %{}]

  def new(status, code, message, opts \\ []) do
    %__MODULE__{
      status: status,
      code: code,
      message: message,
      retryable: Keyword.get(opts, :retryable, false),
      details: Keyword.get(opts, :details, %{})
    }
  end
end
