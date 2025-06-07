defmodule TurboFalcon.Repo do
  use Ecto.Repo,
    otp_app: :turbo_falcon,
    adapter: Ecto.Adapters.SQLite3
end
