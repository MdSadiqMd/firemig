defmodule FiremigCoordinator.Health do
  @moduledoc false

  alias FiremigCoordinator.Repo

  def readiness do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _result} -> {:ok, %{database: "ok"}}
      {:error, _reason} -> {:error, %{database: "unavailable"}}
    end
  end
end
