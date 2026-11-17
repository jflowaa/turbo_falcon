defmodule TurboFalconWeb.HealthController do
  use TurboFalconWeb, :controller

  def show(conn, _params) do
    send_resp(conn, :ok, "ok")
  end
end
