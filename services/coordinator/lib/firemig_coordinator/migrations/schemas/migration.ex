defmodule FiremigCoordinator.Migration do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias FiremigCoordinator.MigrationState

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "migrations" do
    field :sandbox_id, :binary_id
    field :source_worker, :string
    field :destination_worker, :string
    field :idempotency_key, :string
    field :request_hash, :string
    field :phase, :string
    field :epoch_before, :integer
    field :epoch_after, :integer
    field :bytes_total, :integer, default: 0
    field :bytes_transferred, :integer, default: 0
    field :path_selected, :string
    field :snapshot_manifest, :map
    field :snapshot_consumed, :boolean, default: false
    field :resume_issued_at, :utc_datetime_usec
    field :error_code, :string
    field :error_detail, :string
    field :options, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(migration, attrs) do
    migration
    |> cast(attrs, [
      :source_worker,
      :destination_worker,
      :idempotency_key,
      :request_hash,
      :epoch_before,
      :epoch_after,
      :options
    ])
    |> validate_required([
      :source_worker,
      :destination_worker,
      :idempotency_key,
      :request_hash,
      :epoch_before,
      :epoch_after
    ])
    |> put_change(:phase, MigrationState.initial_phase())
    |> unique_constraint(:idempotency_key)
    |> unique_constraint(:sandbox_id, name: :migrations_one_active_per_sandbox)
  end

  def transition_changeset(migration, attrs), do: change(migration, attrs)
end
