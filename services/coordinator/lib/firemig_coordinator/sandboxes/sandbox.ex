defmodule FiremigCoordinator.Sandbox do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "sandboxes" do
    field :epoch, :integer, default: 1
    field :generation, :integer, default: 1
    field :state, :string
    field :worker, :string
    field :region, :string
    field :cpu, :integer
    field :memory_mb, :integer
    field :boot_id, :string
    field :booted_at, :utc_datetime_usec
    field :metadata, :map, default: %{}
    field :active_migration_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(sandbox, attrs) do
    sandbox
    |> cast(attrs, [:region, :worker, :cpu, :memory_mb, :metadata])
    |> validate_required([:region, :worker, :cpu, :memory_mb])
    |> validate_number(:cpu, greater_than: 0)
    |> validate_number(:memory_mb, greater_than: 0)
    |> put_change(:state, "booting")
  end
end
