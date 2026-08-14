defmodule FiremigProxy.AdminRouterTest do
  use ExUnit.Case

  import Plug.Conn
  import Plug.Test

  alias FiremigProxy.AdminRouter

  setup do
    previous_token = Application.get_env(:firemig_proxy, :proxy_token)

    on_exit(fn -> Application.put_env(:firemig_proxy, :proxy_token, previous_token) end)

    Application.put_env(:firemig_proxy, :proxy_token, nil)
    :ok
  end

  test "route lifecycle is exposed through the private API" do
    sandbox_id = "api-#{System.unique_integer([:positive])}"

    create_body = %{
      "sandboxId" => sandbox_id,
      "guestPort" => 8080,
      "endpoint" => %{"host" => "127.0.0.1", "port" => 65_000},
      "epoch" => 1
    }

    create = request(:post, "/internal/routes", create_body)
    assert create.status == 201
    assert %{"phase" => "active", "proxyPort" => proxy_port} = Jason.decode!(create.resp_body)
    assert proxy_port > 0

    cutover = request(:post, "/internal/routes/#{sandbox_id}/begin-cutover", %{})
    assert cutover.status == 200
    assert %{"phase" => "cutover"} = Jason.decode!(cutover.resp_body)

    stale_body = %{
      "endpoint" => %{"host" => "127.0.0.1", "port" => 65_001},
      "epoch" => 1
    }

    stale = request(:put, "/internal/routes/#{sandbox_id}/endpoint", stale_body)
    assert stale.status == 409
    assert %{"error" => "stale_epoch"} = Jason.decode!(stale.resp_body)

    update_body = put_in(stale_body["epoch"], 2)
    update = request(:put, "/internal/routes/#{sandbox_id}/endpoint", update_body)
    assert update.status == 200
    assert %{"epoch" => 2, "phase" => "active"} = Jason.decode!(update.resp_body)

    status = request(:get, "/internal/routes/#{sandbox_id}/status")
    assert status.status == 200

    route = request(:get, "/internal/routes/#{sandbox_id}")
    assert route.status == 200

    delete = request(:delete, "/internal/routes/#{sandbox_id}")
    assert delete.status == 204

    missing = request(:get, "/internal/routes/#{sandbox_id}/status")
    assert missing.status == 404
  end

  test "an occupied preferred port falls back to an available port" do
    {:ok, occupied_socket} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])

    {:ok, {_address, occupied_port}} = :inet.sockname(occupied_socket)
    on_exit(fn -> :gen_tcp.close(occupied_socket) end)

    sandbox_id = "fallback-#{System.unique_integer([:positive])}"

    create =
      request(:post, "/internal/routes", %{
        "sandboxId" => sandbox_id,
        "guestPort" => 8080,
        "preferredProxyPort" => occupied_port,
        "endpoint" => %{"host" => "127.0.0.1", "port" => 65_000},
        "epoch" => 1
      })

    assert create.status == 201
    assert %{"proxyPort" => proxy_port} = Jason.decode!(create.resp_body)
    assert proxy_port != occupied_port
    assert request(:delete, "/internal/routes/#{sandbox_id}").status == 204
  end

  test "health remains public when bearer authentication is enabled" do
    Application.put_env(:firemig_proxy, :proxy_token, "health-secret")

    response = request(:get, "/health")

    assert response.status == 200
    assert %{"status" => "ok"} = Jason.decode!(response.resp_body)
  end

  test "every internal route rejects missing authorization without route details" do
    Application.put_env(:firemig_proxy, :proxy_token, "route-secret")

    routes = [
      {:post, "/internal/routes"},
      {:post, "/internal/routes/missing/begin-cutover"},
      {:put, "/internal/routes/missing/endpoint"},
      {:get, "/internal/routes/missing/status"},
      {:get, "/internal/routes/missing"},
      {:delete, "/internal/routes/missing"}
    ]

    Enum.each(routes, fn {method, path} ->
      response = request(method, path)

      assert response.status == 401
      assert %{"error" => "unauthorized"} = Jason.decode!(response.resp_body)
      assert get_resp_header(response, "www-authenticate") == ["Bearer"]
    end)
  end

  test "malformed and incorrect authorization all return the same response" do
    Application.put_env(:firemig_proxy, :proxy_token, "correct-secret")

    headers = [
      "Basic correct-secret",
      "Bearer",
      "Bearer ",
      "bearer correct-secret",
      "Bearer wrong-secret"
    ]

    Enum.each(headers, fn authorization ->
      response = request(:get, "/internal/routes/missing", nil, authorization)

      assert response.status == 401
      assert response.resp_body == ~s({"error":"unauthorized"})
    end)
  end

  test "unauthorized malformed JSON is rejected before body parsing" do
    Application.put_env(:firemig_proxy, :proxy_token, "correct-secret")

    response =
      :post
      |> conn("/internal/routes", "{")
      |> put_req_header("content-type", "application/json")
      |> AdminRouter.call(AdminRouter.init([]))

    assert response.status == 401
    assert %{"error" => "unauthorized"} = Jason.decode!(response.resp_body)
  end

  test "a valid bearer token reaches internal routing" do
    Application.put_env(:firemig_proxy, :proxy_token, "correct-secret")

    response = request(:get, "/internal/routes/missing", nil, "Bearer correct-secret")

    assert response.status == 404
    assert %{"error" => "not_found"} = Jason.decode!(response.resp_body)
  end

  defp request(method, path, body \\ nil, authorization \\ nil) do
    conn =
      method
      |> conn(path, Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_authorization(authorization)

    AdminRouter.call(conn, AdminRouter.init([]))
  end

  defp put_authorization(conn, nil), do: conn
  defp put_authorization(conn, value), do: put_req_header(conn, "authorization", value)
end
