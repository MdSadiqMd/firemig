defmodule FiremigCoordinator.WorkerClient.Req do
  @moduledoc false

  @behaviour FiremigCoordinator.WorkerClient

  import FiremigCoordinator.WorkerClient.Transport

  @impl true
  def create_sandbox(worker, attrs),
    do: request(worker, :post, "/internal/sandboxes", attrs.epoch, attrs)

  @impl true
  def run_command(worker, sandbox_id, epoch, attrs),
    do: request(worker, :post, "/internal/sandboxes/#{sandbox_id}/commands", epoch, attrs)

  @impl true
  def write_file(worker, sandbox_id, epoch, attrs),
    do: request(worker, :put, "/internal/sandboxes/#{sandbox_id}/files", epoch, attrs)

  @impl true
  def expose_port(worker, sandbox_id, epoch, guest_port),
    do:
      request(
        worker,
        :post,
        "/internal/sandboxes/#{sandbox_id}/ports",
        epoch,
        %{guestPort: guest_port}
      )

  @impl true
  def prepare_migration(worker, sandbox_id, epoch, attrs),
    do:
      request(
        worker,
        :post,
        "/internal/sandboxes/#{sandbox_id}/migrations/#{attrs.migrationId}/prepare",
        epoch,
        attrs
      )

  @impl true
  def probe(worker, sandbox_id, epoch),
    do: request(worker, :post, "/internal/sandboxes/#{sandbox_id}/migration/probe", epoch, %{})

  @impl true
  def precopy(worker, sandbox_id, epoch, attrs),
    do:
      request(worker, :post, "/internal/sandboxes/#{sandbox_id}/migration/precopy", epoch, attrs)

  @impl true
  def pause(worker, sandbox_id, epoch),
    do: request_ok(worker, :post, "/internal/sandboxes/#{sandbox_id}/migration/pause", epoch, %{})

  @impl true
  def snapshot(worker, sandbox_id, epoch, attrs),
    do:
      request(worker, :post, "/internal/sandboxes/#{sandbox_id}/migration/snapshot", epoch, attrs)

  @impl true
  def transfer(worker, sandbox_id, epoch, %{source: source} = attrs) do
    with {:ok, source_base_url} <- worker_url(source) do
      request(
        worker,
        :post,
        "/internal/sandboxes/#{sandbox_id}/migration/transfer",
        epoch,
        Map.put(attrs, :sourceBaseUrl, source_base_url),
        180_000
      )
    end
  end

  @impl true
  def load(worker, sandbox_id, epoch, attrs),
    do:
      request_ok(worker, :post, "/internal/sandboxes/#{sandbox_id}/migration/load", epoch, attrs)

  @impl true
  def resume(worker, sandbox_id, epoch),
    do:
      request_ok(
        worker,
        :post,
        "/internal/sandboxes/#{sandbox_id}/migration/resume",
        epoch,
        %{},
        10_000
      )

  @impl true
  def verify(worker, sandbox_id, epoch, attrs),
    do: request(worker, :post, "/internal/sandboxes/#{sandbox_id}/migration/verify", epoch, attrs)

  @impl true
  def rollback(worker, sandbox_id, epoch, attrs),
    do:
      request_ok(
        worker,
        :post,
        "/internal/sandboxes/#{sandbox_id}/migration/rollback",
        epoch,
        attrs
      )

  @impl true
  def fence_and_cleanup(worker, sandbox_id, epoch, attrs),
    do:
      request_ok(
        worker,
        :post,
        "/internal/sandboxes/#{sandbox_id}/migration/fence-and-cleanup",
        epoch,
        attrs
      )
end
