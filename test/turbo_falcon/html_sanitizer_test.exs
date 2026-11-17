defmodule TurboFalcon.HtmlSanitizerTest do
  use ExUnit.Case, async: true

  alias TurboFalcon.HtmlSanitizer

  describe "sanitize/1" do
    test "keeps the formatting tags used by postings and summaries" do
      html =
        ~s|<h2>Company</h2><p>We are <strong>hiring</strong> and <em>remote</em>.</p><ul><li>Elixir</li></ul>|

      assert HtmlSanitizer.sanitize(html) == html
    end

    test "keeps http, https and mailto links" do
      html =
        ~s|<a href="https://example.com" target="_blank" rel="noopener">site</a> <a href="mailto:jobs@example.com">mail</a>|

      sanitized = HtmlSanitizer.sanitize(html)

      assert sanitized =~ ~s|href="https://example.com"|
      assert sanitized =~ ~s|href="mailto:jobs@example.com"|
      assert sanitized =~ ~s|target="_blank"|
    end

    test "strips script tags" do
      sanitized = HtmlSanitizer.sanitize(~s|<p>hi</p><script>alert(1)</script>|)

      refute sanitized =~ "<script"
      refute sanitized =~ "alert(1)</script>"
    end

    test "strips event handler attributes" do
      sanitized = HtmlSanitizer.sanitize(~s|<p onclick="alert(1)">hi</p>|)

      refute sanitized =~ "onclick"
      assert sanitized =~ "<p>hi</p>"
    end

    test "strips javascript: urls" do
      sanitized = HtmlSanitizer.sanitize(~s|<a href="javascript:alert(1)">click</a>|)

      refute sanitized =~ "javascript:"
      assert sanitized =~ "click"
    end

    test "strips images and inline styles" do
      sanitized =
        HtmlSanitizer.sanitize(
          ~s|<p style="background:url(x)">hi</p><img src="x" onerror="alert(1)">|
        )

      refute sanitized =~ "style="
      refute sanitized =~ "<img"
      refute sanitized =~ "onerror"
    end

    test "only allows _blank as a link target" do
      sanitized = HtmlSanitizer.sanitize(~s|<a href="https://example.com" target="_self">x</a>|)

      refute sanitized =~ "target="
    end

    test "normalizes HN-style unclosed paragraphs" do
      sanitized = HtmlSanitizer.sanitize("Remote | US only<p>We use Elixir<p>Apply now")

      assert sanitized =~ "Remote | US only"
      assert sanitized =~ "<p>"
      assert sanitized =~ "Apply now"
    end

    test "leaves plain text alone" do
      assert HtmlSanitizer.sanitize("just text") == "just text"
    end
  end
end
