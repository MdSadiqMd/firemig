defmodule FiremigCoordinatorWeb.ApiAuth do
  @moduledoc false

  import Plug.Conn

  def init(options), do: options

  def call(conn, _options) do
    authorize(conn, Application.get_env(:firemig_coordinator, :api_token))
  end

  defp authorize(conn, token) when is_binary(token) and byte_size(token) > 0 do
    {bearer?, presented_token} = presented_token(conn)
    matches? = secure_compare(presented_token, token)

    case bearer? and matches? do
      true -> conn
      false -> unauthorized(conn)
    end
  end

  defp authorize(conn, _token), do: conn

  defp presented_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) > 0 -> {true, token}
      _headers -> {false, ""}
    end
  end

  defp secure_compare(presented_token, expected_token) do
    Plug.Crypto.secure_compare(digest(presented_token), digest(expected_token))
  end

  defp digest(token), do: :crypto.hash(:sha256, token)

  defp unauthorized(conn) do
    body =
      Jason.encode!(%{
        error: %{
          code: "UNAUTHORIZED",
          message: "A valid Bearer token is required",
          retryable: false,
          details: %{}
        }
      })

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("www-authenticate", "Bearer")
    |> send_resp(:unauthorized, body)
    |> halt()
  end
end
