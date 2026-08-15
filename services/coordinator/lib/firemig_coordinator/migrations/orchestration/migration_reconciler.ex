defmodule FiremigCoordinator.MigrationReconciler do
  @moduledoc false

  use GenServer

  alias FiremigCoordinator.{MigrationProcesses, Migrations}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: {:ok, %{}, {:continue, :reconcile}}

  @impl true
  def handle_continue(:reconcile, state) do
    Enum.each(Migrations.nonterminal(), fn migration ->
      _ = MigrationProcesses.start_runner(migration.id)
    end)

    {:noreply, state}
  end
end
