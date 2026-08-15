defmodule FiremigCoordinatorWeb.MigrationController do
  use FiremigCoordinatorWeb, :controller

  alias FiremigCoordinator.{MigrationState, Migrations}
  alias FiremigCoordinatorWeb.ControlJSON

  action_fallback FiremigCoordinatorWeb.FallbackController

  def create(conn, %{"id" => sandbox_id} = params) do
    attrs = Map.delete(params, "id")
    idempotency_key = conn |> get_req_header("idempotency-key") |> List.first()

    with {:ok, migration, disposition} <-
           Migrations.start(sandbox_id, attrs, idempotency_key) do
      conn
      |> put_status(create_status(disposition))
      |> json(ControlJSON.migration(migration))
    end
  end

  def show(conn, %{"id" => sandbox_id, "migration_id" => migration_id}) do
    with {:ok, migration} <- Migrations.get(sandbox_id, migration_id) do
      json(conn, ControlJSON.migration(migration))
    end
  end

  def events(conn, %{"id" => sandbox_id, "migration_id" => migration_id}) do
    with {:ok, migration} <- Migrations.get(sandbox_id, migration_id),
         :ok <- Migrations.subscribe(migration.id) do
      sequence = last_event_id(conn)

      conn =
        conn
        |> put_resp_content_type("text/event-stream")
        |> put_resp_header("cache-control", "no-cache")
        |> put_resp_header("connection", "keep-alive")
        |> send_chunked(200)

      case send_events(
             conn,
             Migrations.events_after(migration.id, sequence),
             migration.phase,
             sequence
           ) do
        {:ok, streamed_conn, last_phase, last_sequence} ->
          continue_stream(streamed_conn, last_phase, last_sequence)

        {:closed, streamed_conn} ->
          streamed_conn
      end
    end
  end

  defp continue_stream(conn, phase, sequence) do
    case MigrationState.terminal?(phase) do
      true -> conn
      false -> stream_events(conn, sequence)
    end
  end

  defp stream_events(conn, sequence) do
    receive do
      {:migration_event, %{seq: event_sequence}} when event_sequence <= sequence ->
        stream_events(conn, sequence)

      {:migration_event, event} ->
        case send_event(conn, event) do
          {:ok, streamed_conn} -> continue_stream(streamed_conn, event.phase, event.seq)
          {:error, :closed} -> conn
        end
    after
      15_000 ->
        case chunk(conn, ": keep-alive\n\n") do
          {:ok, streamed_conn} -> stream_events(streamed_conn, sequence)
          {:error, :closed} -> conn
        end
    end
  end

  defp send_events(conn, [], phase, sequence), do: {:ok, conn, phase, sequence}

  defp send_events(conn, events, phase, sequence) do
    Enum.reduce_while(
      events,
      {:ok, conn, phase, sequence},
      fn event, {:ok, current, _phase, _sequence} ->
        case send_event(current, event) do
          {:ok, streamed_conn} -> {:cont, {:ok, streamed_conn, event.phase, event.seq}}
          {:error, :closed} -> {:halt, {:closed, current}}
        end
      end
    )
  end

  defp send_event(conn, event) do
    payload = Jason.encode!(ControlJSON.event(event))
    chunk(conn, "id: #{event.seq}\nevent: #{event_name(event.phase)}\ndata: #{payload}\n\n")
  end

  defp event_name("DONE"), do: "done"
  defp event_name(phase) when phase in ~w(FAILED ROLLED_BACK ORPHANED_AMBIGUOUS), do: "error"
  defp event_name(_phase), do: "progress"

  defp last_event_id(conn) do
    conn
    |> get_req_header("last-event-id")
    |> List.first()
    |> parse_event_id()
  end

  defp parse_event_id(nil), do: 0

  defp parse_event_id(value) do
    case Integer.parse(value) do
      {sequence, ""} when sequence >= 0 -> sequence
      _ -> 0
    end
  end

  defp create_status(:created), do: :accepted
  defp create_status(:replay), do: :ok
end
