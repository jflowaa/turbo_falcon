defmodule TurboFalcon.Observability do
  @moduledoc """
  Wires the platform telemetry contract into the application.

  Traces are exported over OTLP to the platform collector. Logs are ordinary
  stdout lines in the collector's JSON schema; the collector tails them from
  the Podman graph root and forwards them to Loki.
  """

  alias TurboFalcon.Observability.ErrorReporter

  @router_exception_event [:phoenix, :router_dispatch, :exception]

  @doc """
  Attaches the OpenTelemetry instrumentation and the error reporter.

  Call this before the top-level supervisor starts so no requests are missed.
  """
  @spec setup() :: :ok
  def setup do
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:turbo_falcon, :repo])

    :ok = attach_error_reporter()
  rescue
    error ->
      # Telemetry must never prevent the application from booting.
      require Logger
      Logger.warning("Telemetry setup failed: #{Exception.message(error)}")
      :ok
  end

  defp attach_error_reporter do
    handler_id = "turbo-falcon-error-reporter"

    case :telemetry.attach(
           handler_id,
           @router_exception_event,
           &__MODULE__.handle_router_exception/4,
           nil
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc false
  def handle_router_exception(_event, measurements, metadata, _config) do
    conn = Map.get(metadata, :conn)
    kind = Map.get(metadata, :kind, :error)
    reason = Map.get(metadata, :reason)
    stacktrace = Map.get(metadata, :stacktrace, [])
    {exception, stacktrace} = normalise_exception(kind, reason, stacktrace)

    ErrorReporter.report(exception,
      error_code: "http_exception",
      route: route(metadata, conn),
      method: conn && conn.method,
      status: (conn && conn.status) || 500,
      request_id: request_id(conn),
      duration_ms: duration_ms(measurements),
      stacktrace: stacktrace
    )
  rescue
    _ -> :ok
  end

  # Plug wraps controller exceptions. Prefer the underlying exception so the
  # dashboard groups by the real error type and application frame.
  defp normalise_exception(_kind, %Plug.Conn.WrapperError{} = wrapper, _stacktrace) do
    {Exception.normalize(wrapper.kind, wrapper.reason, wrapper.stack), wrapper.stack}
  rescue
    _ -> {wrapper, []}
  end

  defp normalise_exception(kind, reason, stacktrace) do
    {Exception.normalize(kind, reason, stacktrace), stacktrace}
  rescue
    _ -> {%RuntimeError{message: inspect(reason)}, []}
  end

  defp route(metadata, conn) do
    metadata[:route] || (conn && conn.private[:phoenix_route]) || "unmatched"
  end

  defp request_id(nil), do: nil

  defp request_id(conn) do
    Plug.Conn.get_resp_header(conn, "x-request-id")
    |> List.first()
    |> Kernel.||(conn.assigns[:request_id])
  end

  defp duration_ms(%{duration: duration}) when is_integer(duration) do
    System.convert_time_unit(duration, :native, :microsecond) / 1000
  end

  defp duration_ms(_measurements), do: nil
end
