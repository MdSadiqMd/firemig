defmodule FiremigCoordinator.HttpAdapterContractTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias FiremigCoordinator.{ProxyClient, WorkerClient}

  setup {Req.Test, :verify_on_exit!}

  setup do
    keys = [
      :worker_urls,
      :worker_token,
      :worker_req_options,
      :proxy_url,
      :proxy_token,
      :proxy_req_options
    ]

    previous = Map.new(keys, &{&1, Application.get_env(:firemig_coordinator, &1)})

    Application.put_env(:firemig_coordinator, :worker_urls, %{"worker-a" => "http://worker-a"})
    Application.put_env(:firemig_coordinator, :worker_token, "worker-secret")

    Application.put_env(:firemig_coordinator, :worker_req_options,
      plug: {Req.Test, __MODULE__.WorkerStub}
    )

    Application.put_env(:firemig_coordinator, :proxy_url, "http://proxy")
    Application.put_env(:firemig_coordinator, :proxy_token, "proxy-secret")

    Application.put_env(:firemig_coordinator, :proxy_req_options,
      plug: {Req.Test, __MODULE__.ProxyStub}
    )

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:firemig_coordinator, key)
        {key, value} -> Application.put_env(:firemig_coordinator, key, value)
      end)
    end)

    :ok
  end

  test "worker port exposure uses the agent contract and bearer token" do
    Req.Test.expect(__MODULE__.WorkerStub, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/internal/sandboxes/sandbox-1/ports"
      assert get_req_header(conn, "authorization") == ["Bearer worker-secret"]
      assert get_req_header(conn, "x-firemig-epoch") == ["7"]
      assert Jason.decode!(Req.Test.raw_body(conn)) == %{"guestPort" => 8080}

      Req.Test.json(conn, %{"proxyHost" => "worker-a.internal", "proxyPort" => 31_808})
    end)

    assert {:ok, %{"proxyPort" => 31_808}} =
             WorkerClient.Req.expose_port("worker-a", "sandbox-1", 7, 8080)
  end

  test "proxy route lifecycle uses concrete route paths and endpoint payloads" do
    Req.Test.expect(__MODULE__.ProxyStub, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/internal/routes"
      assert get_req_header(conn, "authorization") == ["Bearer proxy-secret"]

      assert Jason.decode!(Req.Test.raw_body(conn)) == %{
               "sandboxId" => "sandbox-1",
               "guestPort" => 8080,
               "preferredProxyPort" => 45_000,
               "endpoint" => %{"host" => "worker-a.internal", "port" => 31_808},
               "epoch" => 7
             }

      Req.Test.json(conn, %{"proxyPort" => 45_000})
    end)

    attrs = %{
      guestPort: 8080,
      preferredProxyPort: 45_000,
      endpoint: %{host: "worker-a.internal", port: 31_808},
      epoch: 7
    }

    assert {:ok, %{"proxyPort" => 45_000}} =
             ProxyClient.Req.expose_port("sandbox-1", attrs)

    Req.Test.expect(__MODULE__.ProxyStub, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/internal/routes/sandbox-1/begin-cutover"
      assert Jason.decode!(Req.Test.raw_body(conn)) == %{}
      Req.Test.json(conn, %{"phase" => "cutover"})
    end)

    assert :ok = ProxyClient.Req.begin_cutover("sandbox-1")

    Req.Test.expect(__MODULE__.ProxyStub, fn conn ->
      assert conn.method == "PUT"
      assert conn.request_path == "/internal/routes/sandbox-1/endpoint"

      assert Jason.decode!(Req.Test.raw_body(conn)) == %{
               "endpoint" => %{"host" => "worker-b.internal", "port" => 32_808},
               "epoch" => 8
             }

      Req.Test.json(conn, %{"phase" => "active", "epoch" => 8})
    end)

    assert :ok =
             ProxyClient.Req.repoint(
               "sandbox-1",
               %{host: "worker-b.internal", port: 32_808},
               8
             )

    Req.Test.expect(__MODULE__.ProxyStub, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/internal/routes/sandbox-1/status"
      Req.Test.json(conn, %{"phase" => "active", "proxyPort" => 45_000})
    end)

    assert {:ok, %{"proxyPort" => 45_000}} = ProxyClient.Req.status("sandbox-1")

    Req.Test.expect(__MODULE__.ProxyStub, fn conn ->
      assert conn.method == "DELETE"
      assert conn.request_path == "/internal/routes/sandbox-1"
      send_resp(conn, 204, "")
    end)

    assert :ok = ProxyClient.Req.delete("sandbox-1")
  end
end
