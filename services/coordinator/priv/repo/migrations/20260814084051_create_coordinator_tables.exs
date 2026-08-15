defmodule FiremigCoordinator.Repo.Migrations.CreateCoordinatorTables do
  use Ecto.Migration

  def change do
    create table(:sandboxes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :epoch, :integer, null: false, default: 1
      add :generation, :integer, null: false, default: 1
      add :state, :string, null: false
      add :worker, :string, null: false
      add :region, :string, null: false
      add :cpu, :integer, null: false
      add :memory_mb, :integer, null: false
      add :boot_id, :string
      add :booted_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}
      add :active_migration_id, :binary_id

      timestamps(type: :utc_datetime_usec)
    end

    create table(:migrations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :sandbox_id, references(:sandboxes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :source_worker, :string, null: false
      add :destination_worker, :string, null: false
      add :idempotency_key, :string, null: false
      add :request_hash, :string, null: false
      add :phase, :string, null: false
      add :epoch_before, :integer, null: false
      add :epoch_after, :integer, null: false
      add :bytes_total, :integer, null: false, default: 0
      add :bytes_transferred, :integer, null: false, default: 0
      add :path_selected, :string
      add :snapshot_manifest, :map
      add :snapshot_consumed, :boolean, null: false, default: false
      add :resume_issued_at, :utc_datetime_usec
      add :error_code, :string
      add :error_detail, :string
      add :options, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:migrations, [:idempotency_key])
    create index(:migrations, [:sandbox_id])

    execute(
      """
      CREATE UNIQUE INDEX migrations_one_active_per_sandbox
      ON migrations(sandbox_id)
      WHERE phase NOT IN ('DONE', 'FAILED', 'ROLLED_BACK', 'ORPHANED_AMBIGUOUS')
      """,
      "DROP INDEX migrations_one_active_per_sandbox"
    )

    create table(:migration_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :migration_id, references(:migrations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :seq, :integer, null: false
      add :phase, :string, null: false
      add :bytes, :integer, null: false, default: 0
      add :detail, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:migration_events, [:migration_id, :seq])

    create table(:ports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :sandbox_id, references(:sandboxes, type: :binary_id, on_delete: :delete_all),
        null: false

      add :guest_port, :integer, null: false
      add :protocol, :string, null: false, default: "tcp"
      add :proxy_host, :string, null: false
      add :proxy_port, :integer, null: false
      add :url, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ports, [:sandbox_id, :guest_port])
  end
end
