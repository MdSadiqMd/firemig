defmodule FiremigCoordinator.Migrations.Validation do
  @moduledoc false

  alias FiremigCoordinator.{Error, Migration, Sandbox}

  def validate_idempotency_key(key) when is_binary(key) and byte_size(key) > 0, do: :ok

  def validate_idempotency_key(_key),
    do: {:error, Error.new(428, "IDEMPOTENCY_KEY_REQUIRED", "Idempotency-Key header is required")}

  def fetch_destination(%{"destination" => destination})
      when is_binary(destination) and byte_size(destination) > 0,
      do: {:ok, destination}

  def fetch_destination(_attrs),
    do: {:error, Error.new(422, "VALIDATION_ERROR", "destination is required")}

  def ensure_running(%Sandbox{state: "running"}), do: :ok

  def ensure_running(%Sandbox{}),
    do: {:error, Error.new(409, "SANDBOX_NOT_RUNNING", "Sandbox is not running")}

  def ensure_destination_changed(%Sandbox{worker: worker}, worker),
    do: {:error, Error.new(422, "DESTINATION_IS_SOURCE", "Destination must differ from source")}

  def ensure_destination_changed(_sandbox, _destination), do: :ok

  def ensure_no_active_migration(%Sandbox{active_migration_id: nil}), do: :ok

  def ensure_no_active_migration(%Sandbox{active_migration_id: migration_id}),
    do:
      {:error,
       Error.new(409, "MIGRATION_IN_PROGRESS", "A migration is already active",
         details: %{migrationId: migration_id}
       )}

  def ensure_unconsumed(%Migration{snapshot_consumed: false}), do: :ok
  def ensure_unconsumed(%Migration{}), do: {:error, :snapshot_already_consumed}

  def error_attrs(reason),
    do: %{error_code: "MIGRATION_STEP_FAILED", error_detail: inspect(reason)}

  def sandbox_not_found, do: Error.new(404, "SANDBOX_NOT_FOUND", "Sandbox not found")

  def idempotency_conflict do
    Error.new(
      409,
      "IDEMPOTENCY_KEY_CONFLICT",
      "Idempotency key was already used with a different request"
    )
  end
end
