defmodule FiremigProxy.Routes do
  @moduledoc "Route lifecycle boundary used by the private admin API."

  alias FiremigProxy.{RouteManager, RouteSupervisor}

  @type endpoint :: %{host: String.t(), port: :inet.port_number()}

  @spec create(map()) :: {:ok, map()} | {:error, term()}
  def create(attrs) do
    with :ok <- validate_route(attrs),
         {:ok, supervisor} <- start_route(attrs),
         {:ok, port} <- RouteSupervisor.listener_port(supervisor),
         {:ok, status} <- RouteManager.set_proxy_port(attrs.sandbox_id, port) do
      {:ok, status}
    else
      {:error, {:already_started, _pid}} ->
        {:error, :already_exists}

      {:error, {:shutdown, {:failed_to_start_child, _child, {:already_started, _pid}}}} ->
        {:error, :already_exists}

      {:error, reason} ->
        {:error, normalize_start_error(reason)}
    end
  end

  @spec begin_cutover(String.t()) :: {:ok, map()} | {:error, term()}
  def begin_cutover(sandbox_id), do: with_manager(sandbox_id, &RouteManager.begin_cutover/1)

  @spec update_endpoint(String.t(), endpoint(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def update_endpoint(sandbox_id, endpoint, epoch) do
    with :ok <- validate_endpoint(endpoint),
         :ok <- validate_epoch(epoch) do
      with_manager(sandbox_id, &RouteManager.update_endpoint(&1, endpoint, epoch))
    end
  end

  @spec status(String.t()) :: {:ok, map()} | {:error, :not_found}
  def status(sandbox_id), do: with_manager(sandbox_id, &RouteManager.status/1)

  @spec delete(String.t()) :: :ok | {:error, :not_found}
  def delete(sandbox_id) do
    case Registry.lookup(FiremigProxy.RouteRegistry, {:supervisor, sandbox_id}) do
      [{pid, _value}] ->
        DynamicSupervisor.terminate_child(FiremigProxy.RouteDynamicSupervisor, pid)

      [] ->
        {:error, :not_found}
    end
  end

  defp start_route(%{preferred_proxy_port: port} = attrs) when is_integer(port) do
    attrs
    |> do_start_route()
    |> retry_without_preferred_port(attrs)
  end

  defp start_route(attrs), do: do_start_route(attrs)

  defp do_start_route(attrs) do
    DynamicSupervisor.start_child(FiremigProxy.RouteDynamicSupervisor, {RouteSupervisor, attrs})
  end

  defp retry_without_preferred_port({:error, reason} = result, attrs) do
    retry_without_preferred_port(result, attrs, listener_port_in_use?(reason))
  end

  defp retry_without_preferred_port(result, _attrs), do: result

  defp retry_without_preferred_port(_result, attrs, true),
    do: do_start_route(%{attrs | preferred_proxy_port: nil})

  defp retry_without_preferred_port(result, _attrs, false), do: result

  defp listener_port_in_use?(:eaddrinuse), do: true

  defp listener_port_in_use?({:shutdown, {:failed_to_start_child, :listener, reason}}),
    do: listener_port_in_use?(reason)

  defp listener_port_in_use?(_reason), do: false

  defp with_manager(sandbox_id, operation) do
    case Registry.lookup(FiremigProxy.RouteRegistry, {:manager, sandbox_id}) do
      [{_pid, _value}] -> call_manager(operation, sandbox_id)
      [] -> {:error, :not_found}
    end
  end

  defp call_manager(operation, sandbox_id) do
    operation.(sandbox_id)
  catch
    :exit, {:noproc, _call} -> {:error, :not_found}
    :exit, {{:nodedown, _node}, _call} -> {:error, :unavailable}
    :exit, _reason -> {:error, :unavailable}
  end

  defp validate_route(%{
         sandbox_id: sandbox_id,
         guest_port: guest_port,
         preferred_proxy_port: preferred_proxy_port,
         endpoint: endpoint,
         epoch: epoch
       })
       when is_binary(sandbox_id) and byte_size(sandbox_id) > 0 and guest_port in 1..65_535 and
              (is_nil(preferred_proxy_port) or preferred_proxy_port in 1..65_535) do
    with :ok <- validate_endpoint(endpoint), do: validate_epoch(epoch)
  end

  defp validate_route(_attrs), do: {:error, :invalid_route}

  defp validate_endpoint(%{host: host, port: port})
       when is_binary(host) and byte_size(host) > 0 and port in 1..65_535,
       do: :ok

  defp validate_endpoint(_endpoint), do: {:error, :invalid_endpoint}

  defp validate_epoch(epoch) when is_integer(epoch) and epoch >= 0, do: :ok
  defp validate_epoch(_epoch), do: {:error, :invalid_epoch}

  defp normalize_start_error({:shutdown, {:failed_to_start_child, :listener, reason}}),
    do: {:listener_start_failed, reason}

  defp normalize_start_error(reason), do: reason
end
