defmodule FiremigCoordinator.MigrationEvent do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "migration_events" do
    field :migration_id, :binary_id
    field :seq, :integer
    field :phase, :string
    field :bytes, :integer, default: 0
    field :detail, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:seq, :phase, :bytes, :detail])
    |> validate_required([:seq, :phase, :bytes])
    |> unique_constraint([:migration_id, :seq])
  end
end
