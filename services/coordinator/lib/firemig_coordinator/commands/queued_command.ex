defmodule FiremigCoordinator.QueuedCommand do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:command_id, :string, autogenerate: false}
  @statuses ~w(publishing pending done failed)

  schema "queued_commands" do
    field :sandbox_id, :binary_id
    field :user_id, :string
    field :idempotency_key, :string
    field :payload, :map
    field :status, :string
    field :partition, :integer
    field :offset, :integer
    field :result, :map
    field :error, :map

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(command, attrs) do
    command
    |> cast(attrs, [:command_id, :sandbox_id, :user_id, :idempotency_key, :payload])
    |> validate_required([:command_id, :sandbox_id, :user_id, :idempotency_key, :payload])
    |> validate_length(:command_id, min: 1)
    |> validate_length(:user_id, min: 1)
    |> validate_length(:idempotency_key, min: 1)
    |> put_change(:status, "publishing")
    |> validate_inclusion(:status, @statuses)
  end

  def status_changeset(command, attrs) do
    command
    |> cast(attrs, [:status, :partition, :offset, :result, :error])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end
end
