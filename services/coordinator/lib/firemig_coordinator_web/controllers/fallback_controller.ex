defmodule FiremigCoordinatorWeb.FallbackController do
  @moduledoc false

  use FiremigCoordinatorWeb, :controller

  alias Ecto.Changeset
  alias FiremigCoordinator.Error

  def call(conn, {:error, %Error{} = error}) do
    conn
    |> put_status(error.status)
    |> json(%{
      error: %{
        code: error.code,
        message: error.message,
        retryable: error.retryable,
        details: error.details
      }
    })
  end

  def call(conn, {:error, %Changeset{} = changeset}) do
    details =
      Changeset.traverse_errors(changeset, fn {message, options} ->
        Enum.reduce(options, message, fn {key, value}, rendered ->
          String.replace(rendered, "%{#{key}}", to_string(value))
        end)
      end)

    call(
      conn,
      {:error, Error.new(422, "VALIDATION_ERROR", "Request validation failed", details: details)}
    )
  end

  def call(conn, {:error, reason}) do
    call(
      conn,
      {:error,
       Error.new(500, "INTERNAL_ERROR", "Coordinator operation failed",
         details: %{reason: inspect(reason)}
       )}
    )
  end
end
