defmodule FiremigCoordinatorWeb.ErrorJSONTest do
  use FiremigCoordinatorWeb.ConnCase, async: true

  test "renders 404" do
    assert FiremigCoordinatorWeb.ErrorJSON.render("404.json", %{}) == %{
             error: %{
               code: "NOT_FOUND",
               message: "Not Found",
               retryable: false,
               details: %{}
             }
           }
  end

  test "renders 500" do
    assert FiremigCoordinatorWeb.ErrorJSON.render("500.json", %{}) ==
             %{
               error: %{
                 code: "INTERNAL_ERROR",
                 message: "Internal Server Error",
                 retryable: false,
                 details: %{}
               }
             }
  end
end
