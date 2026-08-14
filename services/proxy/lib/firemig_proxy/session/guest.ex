defmodule FiremigProxy.Session.Guest do
  @moduledoc false

  alias FiremigProxy.SequenceFilter
  alias FiremigProxy.Session.{Flow, Transport}
  alias FiremigProxy.SessionState

  def handle_guest_data(data, socket, state) do
    {outbound, acknowledgements, state} = filter_guest_data(data, state)

    case Transport.send_client_data(state.client_socket, outbound) do
      :ok -> acknowledge_and_forward(acknowledgements, outbound, socket, state)
      {:error, reason} -> {:stop, {:client_send_failed, reason}, state}
    end
  end

  defp filter_guest_data(data, %{sequence_aware?: false} = state), do: {data, [], state}

  defp filter_guest_data(data, state) do
    {outbound, acknowledgements, sequence_filter} =
      SequenceFilter.feed(state.sequence_filter, data)

    {outbound, acknowledgements, %{state | sequence_filter: sequence_filter}}
  end

  defp acknowledge_and_forward(acknowledgements, outbound, socket, state) do
    case Transport.send_acknowledgements(socket, acknowledgements) do
      :ok -> guest_data_forwarded(outbound, socket, state)
      {:error, _reason} -> Flow.handle_internal_eof(Transport.close_internal(state))
    end
  end

  defp guest_data_forwarded([], socket, state) do
    :ok = :inet.setopts(socket, active: :once)
    {:noreply, state}
  end

  defp guest_data_forwarded(_outbound, socket, state) do
    now = System.monotonic_time(:millisecond)
    {domain, gap_ms} = SessionState.note_guest_data(state.domain, now)
    maybe_report_gap(state.route_manager, gap_ms)
    :ok = :inet.setopts(socket, active: :once)
    {:noreply, %{state | domain: domain}}
  end

  defp maybe_report_gap(_route_manager, nil), do: :ok

  defp maybe_report_gap(route_manager, gap_ms),
    do: send(route_manager, {:cutover_gap, self(), gap_ms})
end
