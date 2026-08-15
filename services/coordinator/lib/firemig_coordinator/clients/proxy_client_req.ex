defmodule FiremigCoordinator.ProxyClient.Req do
  @moduledoc false

  @behaviour FiremigCoordinator.ProxyClient

  @impl true
  def expose_port(sandbox_id, attrs) do
    body = %{
      sandboxId: sandbox_id,
      guestPort: attrs.guestPort,
      endpoint: attrs.endpoint,
      epoch: attrs.epoch
    }

    body = body |> maybe_put_preferred_port(attrs) |> maybe_put_sequence_aware(attrs)
    request(:post, "/internal/routes", body)
  end

  @impl true
  def begin_cutover(sandbox_id),
    do: request_ok(:post, "/internal/routes/#{sandbox_id}/begin-cutover", %{})

  @impl true
  def repoint(sandbox_id, endpoint, epoch) do
    request_ok(
      :put,
      "/internal/routes/#{sandbox_id}/endpoint",
      %{endpoint: endpoint, epoch: epoch}
    )
  end

  @impl true
  def status(sandbox_id), do: request(:get, "/internal/routes/#{sandbox_id}/status", nil)

  @impl true
  def delete(sandbox_id), do: request_ok(:delete, "/internal/routes/#{sandbox_id}", %{})

  defp request_ok(method, path, body) do
    case request(method, path, body) do
      {:ok, _body} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp request(method, path, body) do
    case Req.request(request_options(method, path, body)) do
      {:ok, %Req.Response{status: status, body: response_body}} when status in 200..299 ->
        {:ok, normalize_body(response_body)}

      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:error, {:http, status, response_body}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_body(body) when is_map(body), do: body
  defp normalize_body(_body), do: %{}

  defp maybe_put_preferred_port(body, %{preferredProxyPort: port}) when is_integer(port),
    do: Map.put(body, :preferredProxyPort, port)

  defp maybe_put_preferred_port(body, _attrs), do: body

  defp maybe_put_sequence_aware(body, %{sequenceAware: true}),
    do: Map.put(body, :sequenceAware, true)

  defp maybe_put_sequence_aware(body, _attrs), do: body

  defp request_headers do
    case Application.get_env(:firemig_coordinator, :proxy_token) do
      token when is_binary(token) and byte_size(token) > 0 ->
        [{"authorization", "Bearer #{token}"}]

      _token ->
        []
    end
  end

  defp request_options(method, path, body) do
    [
      method: method,
      url: Application.fetch_env!(:firemig_coordinator, :proxy_url) <> path,
      headers: request_headers(),
      receive_timeout: 30_000,
      retry: false
    ]
    |> maybe_put_json(body)
    |> Keyword.merge(Application.get_env(:firemig_coordinator, :proxy_req_options, []))
  end

  defp maybe_put_json(options, nil), do: options
  defp maybe_put_json(options, body), do: Keyword.put(options, :json, body)
end
