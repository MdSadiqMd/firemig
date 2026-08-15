defmodule FiremigCoordinator.WorkerClient do
  @moduledoc "Boundary for worker-agent control calls."

  @callback create_sandbox(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback run_command(String.t(), String.t(), non_neg_integer(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback write_file(String.t(), String.t(), non_neg_integer(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback expose_port(String.t(), String.t(), non_neg_integer(), pos_integer()) ::
              {:ok, map()} | {:error, term()}
  @callback prepare_migration(String.t(), String.t(), non_neg_integer(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback probe(String.t(), String.t(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  @callback precopy(String.t(), String.t(), non_neg_integer(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback pause(String.t(), String.t(), non_neg_integer()) :: :ok | {:error, term()}
  @callback snapshot(String.t(), String.t(), non_neg_integer(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback transfer(String.t(), String.t(), non_neg_integer(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback load(String.t(), String.t(), non_neg_integer(), map()) :: :ok | {:error, term()}
  @callback resume(String.t(), String.t(), non_neg_integer()) :: :ok | {:error, term()}
  @callback verify(String.t(), String.t(), non_neg_integer(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback rollback(String.t(), String.t(), non_neg_integer(), map()) :: :ok | {:error, term()}
  @callback fence_and_cleanup(String.t(), String.t(), non_neg_integer(), map()) ::
              :ok | {:error, term()}
end
