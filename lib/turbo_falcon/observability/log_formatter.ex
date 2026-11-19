defmodule TurboFalcon.Observability.LogFormatter do
  @moduledoc """
  Formats Logger messages as the platform's one-JSON-object-per-line schema.

  The platform collector tails the container's `k8s-file` log and promotes
  `service`, `version`, and `environment` to resource attributes. `trace_id`
  and `span_id` correlate a log line with its exported span. Only allowlisted
  metadata is emitted so request headers, cookies, and query strings can never
  leak into the log store.
  """

  @service_name "turbo_falcon"

  @allowed_metadata [
    :request_id,
    :error_code,
    :error_message,
    :error_stack,
    :route,
    :method,
    :status,
    :operation,
    :duration_ms,
    :trace_id,
    :span_id
  ]

  @spec format(atom(), term(), Logger.Formatter.date_time_ms(), keyword()) :: iodata()
  def format(level, message, timestamp, metadata) do
    trace_id = trace_id(metadata)
    span_id = span_id(metadata)

    payload =
      %{
        "timestamp" => format_timestamp(timestamp),
        "level" => level_name(level),
        "service" => service_name(),
        "version" => version(),
        "environment" => environment(),
        "message" => message_to_string(message)
      }
      |> put_metadata(metadata)
      |> put_if("trace_id", trace_id)
      |> put_if("span_id", span_id)

    [Jason.encode_to_iodata!(payload), "\n"]
  rescue
    error ->
      fallback(level, message, timestamp, error)
  end

  defp put_metadata(payload, metadata) when is_list(metadata) do
    Enum.reduce(metadata, payload, fn
      {key, value}, acc when key in @allowed_metadata ->
        put_if(acc, Atom.to_string(key), normalise(value))

      _, acc ->
        acc
    end)
  end

  defp put_metadata(payload, _metadata), do: payload

  defp put_if(payload, _key, nil), do: payload
  defp put_if(payload, _key, ""), do: payload
  defp put_if(payload, key, value), do: Map.put(payload, key, value)

  defp normalise(nil), do: nil
  defp normalise(value) when is_binary(value), do: value
  defp normalise(value) when is_boolean(value), do: value
  defp normalise(value) when is_number(value), do: value
  defp normalise(value) when is_atom(value), do: Atom.to_string(value)
  defp normalise(value) when is_list(value), do: inspect(value)
  defp normalise(value) when is_map(value), do: inspect(value)
  defp normalise(value), do: inspect(value)

  defp message_to_string(message) when is_binary(message), do: message

  defp message_to_string(message) when is_list(message) do
    IO.chardata_to_string(message)
  rescue
    _ -> inspect(message)
  end

  defp message_to_string(message), do: inspect(message)

  defp format_timestamp({{year, month, day}, {hour, minute, second, millisecond}}) do
    date = Date.new!(year, month, day)
    time = Time.new!(hour, minute, second, {millisecond * 1000, 3})

    date
    |> NaiveDateTime.new!(time)
    |> NaiveDateTime.to_iso8601()
    |> Kernel.<>("Z")
  rescue
    _ -> DateTime.utc_now() |> DateTime.to_iso8601()
  end

  defp level_name(:emergency), do: "Critical"
  defp level_name(:alert), do: "Critical"
  defp level_name(:critical), do: "Critical"
  defp level_name(:error), do: "Error"
  defp level_name(:warning), do: "Warning"
  defp level_name(:warn), do: "Warning"
  defp level_name(:notice), do: "Information"
  defp level_name(:info), do: "Information"
  defp level_name(:debug), do: "Debug"
  defp level_name(level), do: level |> Atom.to_string() |> String.capitalize()

  defp trace_id(metadata) do
    metadata[:trace_id] || metadata[:otel_trace_id] || current_span_hex(:hex_trace_id)
  end

  defp span_id(metadata) do
    metadata[:span_id] || metadata[:otel_span_id] || current_span_hex(:hex_span_id)
  end

  defp current_span_hex(key) do
    case OpenTelemetry.Tracer.current_span_ctx() do
      :undefined -> nil
      span_ctx -> apply(:otel_span, key, [span_ctx])
    end
  rescue
    _ -> nil
  end

  defp service_name do
    :turbo_falcon
    |> Application.get_env(:observability, [])
    |> Keyword.get(:service, @service_name)
  end

  defp environment do
    :turbo_falcon
    |> Application.get_env(:observability, [])
    |> Keyword.get(:environment, "production")
  end

  defp version do
    case :turbo_falcon |> Application.get_env(:observability, []) |> Keyword.get(:version) do
      nil -> app_version()
      "unknown" -> app_version()
      version -> version
    end
  end

  defp app_version do
    case Application.spec(:turbo_falcon, :vsn) do
      nil -> "unknown"
      vsn -> List.to_string(vsn)
    end
  end

  defp fallback(level, message, timestamp, error) do
    [
      Jason.encode_to_iodata!(%{
        "timestamp" => format_timestamp(timestamp),
        "level" => level_name(level),
        "service" => @service_name,
        "environment" => "production",
        "message" => "log formatting failed: #{Exception.message(error)}",
        "original_message" => inspect(message)
      }),
      "\n"
    ]
  rescue
    _ -> "[log formatting failed]\n"
  end
end
