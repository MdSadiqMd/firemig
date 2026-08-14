defmodule FiremigProxy.AdminRouter.Params do
  @moduledoc false

  def route_attrs(
        %{
          "sandboxId" => sandbox_id,
          "guestPort" => guest_port,
          "endpoint" => %{"host" => host, "port" => endpoint_port},
          "epoch" => epoch
        } = params
      ) do
    {:ok,
     %{
       sandbox_id: sandbox_id,
       guest_port: guest_port,
       preferred_proxy_port: Map.get(params, "preferredProxyPort"),
       endpoint: %{host: host, port: endpoint_port},
       epoch: epoch,
       sequence_aware?: Map.get(params, "sequenceAware", false)
     }}
  end

  def route_attrs(_params), do: {:error, :invalid_route}

  def endpoint_attrs(%{
        "endpoint" => %{"host" => host, "port" => port},
        "epoch" => epoch
      }) do
    {:ok, %{host: host, port: port}, epoch}
  end

  def endpoint_attrs(_params), do: {:error, :invalid_endpoint}
end
