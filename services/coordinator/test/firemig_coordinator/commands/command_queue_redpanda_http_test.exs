defmodule FiremigCoordinator.CommandQueue.RedpandaHTTPTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias FiremigCoordinator.CommandQueue.RedpandaHTTP

  setup {Req.Test, :verify_on_exit!}

  setup do
    previous_options = Application.get_env(:firemig_coordinator, :redpanda_req_options)
    previous_url = Application.fetch_env!(:firemig_coordinator, :redpanda_http_url)

    Application.put_env(:firemig_coordinator, :redpanda_http_url, "http://redpanda")

    Application.put_env(:firemig_coordinator, :redpanda_req_options,
      plug: {Req.Test, __MODULE__.RedpandaStub}
    )

    on_exit(fn ->
      Application.put_env(:firemig_coordinator, :redpanda_http_url, previous_url)

      case previous_options do
        nil -> Application.delete_env(:firemig_coordinator, :redpanda_req_options)
        options -> Application.put_env(:firemig_coordinator, :redpanda_req_options, options)
      end
    end)

    :ok
  end

  test "publishes Kafka JSON with the user key and parses the offset" do
    Req.Test.expect(__MODULE__.RedpandaStub, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/topics/firemig.commands"

      assert get_req_header(conn, "content-type") == [
               "application/vnd.kafka.json.v2+json"
             ]

      assert get_req_header(conn, "accept") == ["application/vnd.kafka.v2+json"]

      assert Jason.decode!(Req.Test.raw_body(conn)) == %{
               "records" => [
                 %{
                   "partition" => 0,
                   "key" => "user-a",
                   "value" => %{
                     "commandId" => "command-1",
                     "userId" => "user-a",
                     "sandboxId" => "sandbox-1",
                     "idempotencyKey" => "idempotency-1",
                     "payload" => %{"command" => "echo queued"}
                   }
                 }
               ]
             }

      Req.Test.json(conn, %{
        "offsets" => [%{"partition" => 0, "offset" => 42, "error_code" => nil}]
      })
    end)

    assert {:ok, %{partition: 0, offset: 42}} =
             RedpandaHTTP.publish(%{
               command_id: "command-1",
               user_id: "user-a",
               sandbox_id: "sandbox-1",
               idempotency_key: "idempotency-1",
               payload: %{"command" => "echo queued"}
             })
  end

  test "reads partition records from offset zero as Kafka JSON" do
    Req.Test.expect(__MODULE__.RedpandaStub, fn conn ->
      conn = fetch_query_params(conn)
      assert conn.method == "GET"
      assert conn.request_path == "/topics/firemig.commands/partitions/0/records"
      assert conn.query_params["offset"] == "0"
      assert conn.query_params["timeout"] == "1000"
      assert conn.query_params["max_bytes"] == "1048576"
      assert get_req_header(conn, "accept") == ["application/vnd.kafka.json.v2+json"]

      Req.Test.json(conn, [
        %{
          "topic" => "firemig.commands",
          "partition" => 0,
          "offset" => 7,
          "key" => "user-a",
          "value" => %{
            "commandId" => "command-1",
            "userId" => "user-a",
            "sandboxId" => "sandbox-1",
            "idempotencyKey" => "idempotency-1",
            "payload" => %{"command" => "echo queued"}
          }
        }
      ])
    end)

    assert {:ok, [record]} = RedpandaHTTP.records()
    assert record.partition == 0
    assert record.offset == 7
    assert record.key == "user-a"
    assert record.value["commandId"] == "command-1"
  end
end
