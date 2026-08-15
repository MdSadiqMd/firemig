defmodule FiremigCoordinatorWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  def render(template, _assigns) do
    message = Phoenix.Controller.status_message_from_template(template)

    %{
      error: %{
        code: default_code(template),
        message: message,
        retryable: false,
        details: %{}
      }
    }
  end

  defp default_code("404.json"), do: "NOT_FOUND"
  defp default_code("500.json"), do: "INTERNAL_ERROR"
  defp default_code(_template), do: "REQUEST_ERROR"
end
