defmodule FiremigCoordinator.Port do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "ports" do
    field :sandbox_id, :binary_id
    field :guest_port, :integer
    field :protocol, :string, default: "tcp"
    field :proxy_host, :string
    field :proxy_port, :integer
    field :url, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(port, attrs) do
    port
    |> cast(attrs, [:guest_port, :protocol, :proxy_host, :proxy_port, :url])
    |> validate_required([:guest_port, :protocol, :proxy_host, :proxy_port, :url])
    |> validate_number(:guest_port, greater_than: 0, less_than: 65_536)
    |> validate_number(:proxy_port, greater_than: 0, less_than: 65_536)
    |> unique_constraint([:sandbox_id, :guest_port])
    |> unique_constraint(:sandbox_id, name: :ports_one_per_sandbox)
  end
end
