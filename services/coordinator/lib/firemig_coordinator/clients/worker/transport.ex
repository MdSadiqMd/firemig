defmodule FiremigCoordinator.WorkerClient.Transport do
  @moduledoc false

  def request_ok(worker, method, path, epoch, body, timeout \\ 30_000) do
    case request(worker, method, path, epoch, body, timeout) do
      {:ok, _body} -> :ok
      {:error, _reason} = error -> error
    end
  end

  def request(worker, method, path, epoch, body, timeout \\ 30_000) do
    with {:ok, base_url} <- worker_url(worker),
         {:ok, response} <-
           Req.request(request_options(method, base_url, path, epoch, body, timeout)) do
      normalize_response(response)
    else
      {:error, %Req.TransportError{reason: :timeout}} -> {:error, :timeout}
      {:error, reason} -> {:error, reason}
    end
  end

  def worker_url(worker) do
    :firemig_coordinator
    |> Application.fetch_env!(:worker_urls)
    |> Map.fetch(worker)
  end

  defp request_headers(epoch) do
    [{"x-firemig-epoch", Integer.to_string(epoch)}]
    |> maybe_put_bearer(Application.get_env(:firemig_coordinator, :worker_token))
  end

  defp maybe_put_bearer(headers, token) when is_binary(token) and byte_size(token) > 0,
    do: [{"authorization", "Bearer #{token}"} | headers]

  defp maybe_put_bearer(headers, _token), do: headers

  defp request_options(method, base_url, path, epoch, body, timeout) do
    [
      method: method,
      url: base_url <> path,
      headers: request_headers(epoch),
      json: body,
      receive_timeout: timeout,
      retry: false
    ]
    |> Keyword.merge(Application.get_env(:firemig_coordinator, :worker_req_options, []))
  end

  defp normalize_response(%Req.Response{status: status, body: body}) when status in 200..299,
    do: {:ok, normalize_body(body)}

  defp normalize_response(%Req.Response{status: status, body: body}),
    do: {:error, {:http, status, body}}

  defp normalize_body(body) when is_map(body), do: body
  defp normalize_body(_body), do: %{}
end
