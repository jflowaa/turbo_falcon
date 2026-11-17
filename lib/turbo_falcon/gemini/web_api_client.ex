defmodule TurboFalcon.Gemini.WebApiClient do
  @base_url "https://generativelanguage.googleapis.com/v1beta/"
  @system_prompt """
  You take in a job posting found on Hacker News thread and create a detailed summary.
  You should break up the posting into the following categories:
  - Company name
  - URL to company home page (Make a link if possible that opens in a new tab)
  - Job positions available (including salary range)
  - Technologies used

  Each category should be clearly defined and its own section. The overall summary is not a list
  however. It is a body of text that may contain lists, links, and other HTML formatting. Avoid
  putting an overall header for the summary. If the job posting gives details about the company,
  then include that information in the summary. Try and reduce padding between categories. It
  should look compact when rendered in a card. Even though it should be compact it should still
  contain a complete summary of the job posting. Remember, if the posting contained flavor text
  then include that in the summary as well in some fashion. You want to bring out the personality
  of the user that posted the job posting.

  Sometimes not all information is available. This is fine, do not guess what
  the values could be and instead indicate that the information is not available.

  You should also list out important information such as:
  - The location the work is done in. Such as remote, hybrid, in office
  - Any restrictions to country, states, and timezones
  - Call out any information specific to applying
  - Any other requirements such as "must have C++ experience" and "must be in office 3 days a week"
  - Some job postings may have a salary range, if so include that in the summary
  - Some jobs offer sponsorship/visa, if so include that in the summary

  This summary you generate will be in HTML to feel free to create links
  (open in a new tab when clicked), lists, and convert bot hardening techniques to avoid
  scrapping emails and URLs and just mutate those to be more human friendly readable.
  For example something like "example dot com" would be "example.com" or "bob smith at
  example dot com" would be "bobsmith@example.com".

  Your response should just be in HTML format, no additional flavor text and as a reminder
  return back your response in HTML. Do not put the response in a code block (```). The HTML should not
  contain headers like "Here is the summary of the job posting" or "The job posting is as follows".
  """

  def new do
    Req.new(
      base_url: @base_url,
      receive_timeout: 30_000,
      # POSTs are excluded from Req's default `:safe_transient` retry policy.
      retry: :transient,
      finch: TurboFalcon.Gemini.Finch
    )
  end

  def get_summary_of_job_posting(client, posting, model \\ "gemini-2.5-flash") do
    body = %{
      "system_instruction" => %{
        "parts" => [
          %{"text" => @system_prompt}
        ]
      },
      "contents" => [
        %{
          "parts" => [
            %{"text" => posting}
          ]
        }
      ]
    }

    Req.post(
      client,
      url: "models/#{model}:generateContent?key=#{System.get_env("GEMINI_API_KEY")}",
      headers: [{"content-type", "application/json"}],
      json: body
    )
  end
end
