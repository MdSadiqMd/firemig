defmodule FiremigCoordinatorWeb.ApiAuthControllerTest do
  use FiremigCoordinatorWeb.ConnCase, async: false

  setup do
    previous_token = Application.get_env(:firemig_coordinator, :api_token)

    on_exit(fn ->
      case previous_token do
        nil -> Application.delete_env(:firemig_coordinator, :api_token)
        token -> Application.put_env(:firemig_coordinator, :api_token, token)
      end
    end)

    :ok
  end

  test "rejects missing and invalid bearer credentials with the standard envelope", %{conn: conn} do
    Application.put_env(:firemig_coordinator, :api_token, "public-secret")
    sandbox_id = Ecto.UUID.generate()

    response = conn |> get("/v1/sandboxes/#{sandbox_id}") |> json_response(401)

    assert response == %{
             "error" => %{
               "code" => "UNAUTHORIZED",
               "message" => "A valid Bearer token is required",
               "retryable" => false,
               "details" => %{}
             }
           }

    invalid_response =
      build_conn()
      |> put_req_header("authorization", "Bearer wrong-secret")
      |> get("/v1/sandboxes/#{sandbox_id}")
      |> json_response(401)

    assert invalid_response == response
  end

  test "accepts the configured bearer token", %{conn: conn} do
    Application.put_env(:firemig_coordinator, :api_token, "public-secret")
    sandbox_id = Ecto.UUID.generate()

    response =
      conn
      |> put_req_header("authorization", "Bearer public-secret")
      |> get("/v1/sandboxes/#{sandbox_id}")
      |> json_response(404)

    assert response["error"]["code"] == "SANDBOX_NOT_FOUND"
  end

  test "authentication is optional when API_TOKEN is not configured", %{conn: conn} do
    Application.delete_env(:firemig_coordinator, :api_token)

    response =
      conn
      |> get("/v1/sandboxes/#{Ecto.UUID.generate()}")
      |> json_response(404)

    assert response["error"]["code"] == "SANDBOX_NOT_FOUND"
  end

  test "protects SSE routes", %{conn: conn} do
    Application.put_env(:firemig_coordinator, :api_token, "public-secret")

    response =
      conn
      |> put_req_header("accept", "text/event-stream")
      |> get("/v1/sandboxes/#{Ecto.UUID.generate()}/migrations/#{Ecto.UUID.generate()}/events")
      |> json_response(401)

    assert response["error"]["code"] == "UNAUTHORIZED"
  end

  test "healthz is unauthenticated and checks database readiness", %{conn: conn} do
    Application.put_env(:firemig_coordinator, :api_token, "public-secret")

    assert conn |> get("/healthz") |> json_response(200) == %{
             "status" => "ok",
             "checks" => %{"database" => "ok"}
           }
  end
end
