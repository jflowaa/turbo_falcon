# Hacker News Who's Hiring Aggregator

This app is broken up into a few domains:

- Every 30 minutes on the hour a job runs powered by [Quantum](https://github.com/quantum-elixir/quantum-core). This job then goes and fetches recent who's hiring threads and checks for any new postings. These postings are stored in a SQLite database
- GenStage is also used for summarizing the job postings. The producer just checks for any recent postings that have not yet been summarized and sends those to the consumer. If consumer gets rate limited by Gemini then it'll sleep for 60 seconds. The Gemini model used is `gemini-2.0-flash`
- Phoenix/LiveView is used for displaying the job postings and providing soft real time interactions with the user

You'll need a Gemini API key set in the env var `GEMINI_API_KEY`.

To start:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
