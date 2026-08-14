defmodule FiremigProxy.AdminRouter.Response do
  @moduledoc false

  import Plug.Conn

  def error(conn, :not_found), do: json(conn, 404, %{error: "not_found"})
  def error(conn, :already_exists), do: json(conn, 409, %{error: "already_exists"})
  def error(conn, :stale_epoch), do: json(conn, 409, %{error: "stale_epoch"})

  def error(conn, :invalid_transition),
    do: json(conn, 409, %{error: "invalid_transition"})

  def error(conn, reason) when reason in [:invalid_route, :invalid_endpoint, :invalid_epoch],
    do: json(conn, 422, %{error: Atom.to_string(reason)})

  def error(conn, {:bad_request, message}),
    do: json(conn, 400, %{error: "bad_request", detail: message})

  def error(conn, reason), do: json(conn, 503, %{error: "unavailable", detail: inspect(reason)})

  def json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
