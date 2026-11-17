defmodule TurboFalcon.HtmlSanitizer do
  @moduledoc """
  Allowlist sanitizer for HTML from untrusted sources.

  Both Hacker News comments and LLM-generated summaries are rendered with
  `Phoenix.HTML.raw/1`, so anything that reaches the browser has to pass through
  `sanitize/1` first.

  Only the tags used by job postings and summaries are allowed. Attributes that
  can execute code or load remote resources (`on*`, `style`, `src`, `srcset`)
  are dropped. Links may only use the `http`, `https` and `mailto` schemes, and
  `target` is restricted to `_blank`.

  Unknown tags are stripped but their text content is kept, except for
  `<script>` and `<style>` blocks, which are removed together with their
  contents.
  """

  @dropped_blocks ~r/<(script|style)\b[^>]*>.*?<\/\1\s*>/is

  defmodule Scrubber do
    @moduledoc false

    use HtmlSanitizeEx

    allow_tag_with_uri_attributes("a", ["href"], ["http", "https", "mailto"])
    allow_tag_with_this_attribute_values("a", "target", ["_blank"])
    allow_tag_with_these_attributes("a", ["title", "rel"])

    allow_tag_with_these_attributes("p", [])
    allow_tag_with_these_attributes("br", [])
    allow_tag_with_these_attributes("ul", [])
    allow_tag_with_these_attributes("ol", [])
    allow_tag_with_these_attributes("li", [])
    allow_tag_with_these_attributes("strong", [])
    allow_tag_with_these_attributes("em", [])
    allow_tag_with_these_attributes("b", [])
    allow_tag_with_these_attributes("i", [])
    allow_tag_with_these_attributes("u", [])
    allow_tag_with_these_attributes("code", [])
    allow_tag_with_these_attributes("pre", [])
    allow_tag_with_these_attributes("blockquote", [])
    allow_tag_with_these_attributes("h1", [])
    allow_tag_with_these_attributes("h2", [])
    allow_tag_with_these_attributes("h3", [])
    allow_tag_with_these_attributes("h4", [])
    allow_tag_with_these_attributes("hr", [])
  end

  @doc """
  Scrubs `html`, returning markup that is safe to render as raw HTML.

  `nil` becomes an empty string so callers can pass nullable database columns.
  """
  def sanitize(nil), do: ""

  def sanitize(html) when is_binary(html) do
    html
    |> then(&Regex.replace(@dropped_blocks, &1, ""))
    |> Scrubber.sanitize()
  end
end
