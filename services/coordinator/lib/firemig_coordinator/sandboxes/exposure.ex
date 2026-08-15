defmodule FiremigCoordinator.Sandboxes.Exposure do
  @moduledoc false

  alias FiremigCoordinator.Sandboxes.Clients
  alias FiremigCoordinator.{Error, Port, Repo}

  def validate_guest_port(port) when is_integer(port) and port in 1..65_535, do: {:ok, port}

  def validate_guest_port(_port),
    do: {:error, Error.new(422, "VALIDATION_ERROR", "guestPort must be between 1 and 65535")}

  def disposition(sandbox_id, guest_port) do
    case Repo.get_by(Port, sandbox_id: sandbox_id) do
      %Port{guest_port: ^guest_port} = port ->
        {:ok, {:existing, port}}

      %Port{} = port ->
        {:error,
         Error.new(422, "ONE_PORT_PER_SANDBOX", "Only one exposed port is supported",
           details: %{existingGuestPort: port.guest_port, requestedGuestPort: guest_port}
         )}

      nil ->
        {:ok, :new}
    end
  end

  def expose({:existing, port}, _sandbox, _attrs, _guest_port), do: {:ok, port, :replay}

  def expose(:new, sandbox, attrs, guest_port) do
    with {:ok, exposure} <-
           Clients.worker().expose_port(sandbox.worker, sandbox.id, sandbox.epoch, guest_port),
         {:ok, endpoint} <- worker_endpoint(exposure),
         {:ok, route} <- create_or_fetch_proxy_route(sandbox, attrs, guest_port, endpoint) do
      insert_port(sandbox.id, attrs, guest_port, route)
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, {:invalid_worker_endpoint, _exposure} = reason} ->
        {:error, Clients.upstream_error("INVALID_WORKER_ENDPOINT", reason)}

      {:error, reason} ->
        {:error, Clients.upstream_error("PORT_SETUP_FAILED", reason)}
    end
  end

  defp insert_port(sandbox_id, request_attrs, guest_port, route) do
    proxy_host = Application.fetch_env!(:firemig_coordinator, :proxy_public_host)
    proxy_port = route["proxyPort"]

    attrs = %{
      guest_port: guest_port,
      protocol: Map.get(request_attrs, "protocol", "tcp"),
      proxy_host: proxy_host,
      proxy_port: proxy_port,
      url: "tcp://#{proxy_host}:#{proxy_port}"
    }

    case Repo.insert(Port.changeset(%Port{sandbox_id: sandbox_id}, attrs)) do
      {:ok, inserted} -> {:ok, inserted, :created}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp create_or_fetch_proxy_route(sandbox, attrs, guest_port, endpoint) do
    route_attrs = proxy_route_attrs(attrs, guest_port, endpoint, sandbox.epoch)

    case Clients.proxy().expose_port(sandbox.id, route_attrs) do
      {:error, {:http, 409, _body}} -> Clients.proxy().status(sandbox.id)
      result -> result
    end
  end

  defp proxy_route_attrs(attrs, guest_port, endpoint, epoch) do
    %{
      guestPort: guest_port,
      endpoint: endpoint,
      epoch: epoch,
      sequenceAware: Map.get(attrs, "sequenceAware", false),
      preferredProxyPort:
        attrs["preferredProxyPort"] ||
          Application.get_env(:firemig_coordinator, :default_proxy_port, 8080)
    }
  end

  defp worker_endpoint(%{"proxyHost" => host, "proxyPort" => port})
       when is_binary(host) and is_integer(port) and port in 1..65_535,
       do: {:ok, %{host: host, port: port}}

  defp worker_endpoint(exposure), do: {:error, {:invalid_worker_endpoint, exposure}}
end
