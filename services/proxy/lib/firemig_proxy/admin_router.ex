defmodule FiremigProxy.AdminRouter do
  @moduledoc false

  use Plug.Router
  use Plug.ErrorHandler

  import FiremigProxy.AdminRouter.Params
  import FiremigProxy.AdminRouter.Response

  alias FiremigProxy.AdminRouter.Auth
  alias FiremigProxy.Routes

  plug(Auth)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:match)
  plug(:dispatch)

  get "/health" do
    json(conn, 200, %{status: "ok"})
  end

  post "/internal/routes" do
    with {:ok, attrs} <- route_attrs(conn.body_params),
         {:ok, status} <- Routes.create(attrs) do
      json(conn, 201, status)
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  post "/internal/routes/:sandbox_id/begin-cutover" do
    case Routes.begin_cutover(sandbox_id) do
      {:ok, status} -> json(conn, 200, status)
      {:error, reason} -> error(conn, reason)
    end
  end

  put "/internal/routes/:sandbox_id/endpoint" do
    with {:ok, endpoint, epoch} <- endpoint_attrs(conn.body_params),
         {:ok, status} <- Routes.update_endpoint(sandbox_id, endpoint, epoch) do
      json(conn, 200, status)
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  get "/internal/routes/:sandbox_id/status" do
    case Routes.status(sandbox_id) do
      {:ok, status} -> json(conn, 200, status)
      {:error, reason} -> error(conn, reason)
    end
  end

  get "/internal/routes/:sandbox_id" do
    case Routes.status(sandbox_id) do
      {:ok, status} -> json(conn, 200, status)
      {:error, reason} -> error(conn, reason)
    end
  end

  delete "/internal/routes/:sandbox_id" do
    case Routes.delete(sandbox_id) do
      :ok -> send_resp(conn, 204, "")
      {:error, reason} -> error(conn, reason)
    end
  end

  match _ do
    error(conn, :not_found)
  end

  @impl Plug.ErrorHandler
  def handle_errors(conn, %{reason: %{__exception__: true} = exception}) do
    error(conn, {:bad_request, Exception.message(exception)})
  end

  def handle_errors(conn, %{reason: reason}),
    do: error(conn, {:bad_request, inspect(reason)})
end
