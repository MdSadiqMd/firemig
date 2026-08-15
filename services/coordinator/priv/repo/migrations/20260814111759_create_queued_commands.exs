defmodule FiremigCoordinator.Repo.Migrations.CreateQueuedCommands do
  use Ecto.Migration

  def change do
    create table(:queued_commands, primary_key: false) do
      add :command_id, :string, primary_key: true

      add :sandbox_id, references(:sandboxes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, :string, null: false
      add :idempotency_key, :string, null: false
      add :payload, :map, null: false
      add :status, :string, null: false
      add :partition, :integer
      add :offset, :integer
      add :result, :map
      add :error, :map

      timestamps(type: :utc_datetime_usec)
    end

    create index(:queued_commands, [:status])
    create index(:queued_commands, [:user_id, :status])
    create index(:queued_commands, [:sandbox_id, :status])
  end
end
