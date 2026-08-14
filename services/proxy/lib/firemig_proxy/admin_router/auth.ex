defmodule FiremigProxy.AdminRouter.Auth do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias FiremigProxy.AdminRouter.Response

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    authenticate_path(conn, internal_path?(conn.request_path))
  end

  defp authenticate_path(conn, false), do: conn

  defp authenticate_path(conn, true) do
    authenticate_token(conn, Application.get_env(:firemig_proxy, :proxy_token))
  end

  defp authenticate_token(conn, nil), do: conn
  defp authenticate_token(conn, ""), do: conn

  defp authenticate_token(conn, expected_token) when is_binary(expected_token) do
    candidate_hash = :crypto.hash(:sha256, bearer_token(conn))
    expected_hash = :crypto.hash(:sha256, expected_token)

    authorize(conn, Plug.Crypto.secure_compare(candidate_hash, expected_hash))
  end

  defp authorize(conn, true), do: conn

  defp authorize(conn, false) do
    conn
    |> put_resp_header("www-authenticate", "Bearer")
    |> Response.json(401, %{error: "unauthorized"})
    |> halt()
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _headers -> ""
    end
  end

  defp internal_path?("/internal"), do: true
  defp internal_path?("/internal/" <> _path), do: true
  defp internal_path?(_path), do: false
end
