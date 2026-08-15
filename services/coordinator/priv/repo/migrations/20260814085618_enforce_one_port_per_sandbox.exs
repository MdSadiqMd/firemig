defmodule FiremigCoordinator.Repo.Migrations.EnforceOnePortPerSandbox do
  use Ecto.Migration

  def change do
    create unique_index(:ports, [:sandbox_id], name: :ports_one_per_sandbox)
  end
end
