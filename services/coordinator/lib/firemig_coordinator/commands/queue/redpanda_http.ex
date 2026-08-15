defmodule FiremigCoordinator.CommandQueue.RedpandaHTTP do
  @moduledoc false

  @behaviour FiremigCoordinator.CommandQueue

  alias FiremigCoordinator.CommandQueue.RedpandaParser

  @kafka_json "application/vnd.kafka.json.v2+json"
  @kafka_metadata "application/vnd.kafka.v2+json"

  @impl true
  def publish(command) do
    body = %{
      records: [
        %{
          partition: 0,
          key: command.user_id,
          value: %{
            commandId: command.command_id,
            userId: command.user_id,
            sandboxId: command.sandbox_id,
            idempotencyKey: command.idempotency_key,
            payload: command.payload
          }
        }
      ]
    }

    with {:ok, response} <-
           request(:post, topic_path(),
             headers: [{"accept", @kafka_metadata}, {"content-type", @kafka_json}],
             json: body
           ),
         {:ok, metadata} <- RedpandaParser.publish_response(response.body) do
      {:ok, metadata}
    end
  end

  @impl true
  def records do
    query = [
      offset: 0,
      timeout: 1000,
      max_bytes: Application.fetch_env!(:firemig_coordinator, :redpanda_max_bytes)
    ]

    with {:ok, response} <-
           request(:get, records_path(), headers: [{"accept", @kafka_json}], params: query),
         {:ok, records} <- RedpandaParser.records(response.body) do
      {:ok, records}
    end
  end

  defp request(method, path, options) do
    request_options =
      [
        method: method,
        url: base_url() <> path,
        receive_timeout: 5_000,
        retry: false
      ]
      |> Keyword.merge(options)
      |> Keyword.merge(Application.get_env(:firemig_coordinator, :redpanda_req_options, []))

    case Req.request(request_options) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp base_url do
    :firemig_coordinator
    |> Application.fetch_env!(:redpanda_http_url)
    |> String.trim_trailing("/")
  end

  defp topic_path,
    do: "/topics/#{Application.fetch_env!(:firemig_coordinator, :command_queue_topic)}"

  defp records_path, do: topic_path() <> "/partitions/0/records"
end
