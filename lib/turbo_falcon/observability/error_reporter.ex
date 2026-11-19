defmodule TurboFalcon.Observability.ErrorReporter do
  @moduledoc """
  Emits exactly one allowlisted error record per reported failure.

  The record is a normal `level=Error` log line with a stable `error_code`.
  Reporting is best-effort and never raises into the caller.
  """

  require Logger

  @default_error_code "internal_error"

  @type context ::
          keyword()
          | %{
              optional(atom()) => term()
            }

  @doc """
  Reports an exception.
  """
  @spec report(Exception.t(), context()) :: :ok
  def report(exception, context \\ []) do
    context = Map.new(context)

    try do
      fields =
        %{
          error_code: error_code(context),
          error_message: text(Exception.message(exception)),
          error_stack:
            text(Exception.format(:error, exception, Map.get(context, :stacktrace, []))),
          route: route(context)
        }
        |> put_context(context)

      log_error(fields)
    rescue
      _ -> :ok
    end

    :ok
  end

  @doc """
  Reports a non-exception failure (a bad upstream status, a failed changeset,
  an exhausted retry, and so on).
  """
  @spec report_message(term(), term(), context()) :: :ok
  def report_message(error_code, message, context \\ []) do
    context = Map.new(context)

    try do
      fields =
        %{
          error_code: to_string(error_code),
          error_message: text(message),
          error_stack: text(Map.get(context, :stacktrace, "")),
          route: route(context)
        }
        |> put_context(context)

      log_error(fields)
    rescue
      _ -> :ok
    end

    :ok
  end

  @metadata_keys [
    :error_code,
    :error_message,
    :error_stack,
    :route,
    :request_id,
    :method,
    :status,
    :operation,
    :duration_ms
  ]

  defp log_error(fields) do
    metadata =
      Enum.reduce(@metadata_keys, [], fn key, acc ->
        case Map.get(fields, key) do
          nil -> acc
          value -> [{key, value} | acc]
        end
      end)

    Logger.error("Unhandled error reported", metadata)
  end

  defp put_context(fields, context) do
    Enum.reduce(
      [:request_id, :method, :status, :operation, :duration_ms],
      fields,
      fn key, acc ->
        case Map.get(context, key) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end
    )
  end

  defp error_code(context) do
    case Map.get(context, :error_code) do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      _ -> @default_error_code
    end
  end

  defp route(context) do
    case Map.get(context, :route) do
      value when is_binary(value) and value != "" -> value
      _ -> "unmatched"
    end
  end

  defp text(nil), do: ""
  defp text(value) when is_binary(value), do: value
  defp text(value), do: inspect(value)
end
