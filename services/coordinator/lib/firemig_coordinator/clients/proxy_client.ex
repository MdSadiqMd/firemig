defmodule FiremigCoordinator.ProxyClient do
  @moduledoc "Boundary for session-proxy control calls."

  @callback expose_port(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback begin_cutover(String.t()) :: :ok | {:error, term()}
  @callback repoint(String.t(), map(), non_neg_integer()) :: :ok | {:error, term()}
  @callback status(String.t()) :: {:ok, map()} | {:error, term()}
  @callback delete(String.t()) :: :ok | {:error, term()}
end
