# Turbo Falcon

Turbo Falcon is a Phoenix + LiveView app that aggregates Hacker News “Who is hiring?” posts, stores them in SQLite, and summarizes postings for faster browsing.

## How it works

- **Thread ingestion (Quantum scheduler):** Runs every 30 minutes, fetches recent HN submissions for `whoishiring`, detects “Ask HN: Who is hiring?” threads, and upserts new/changed postings.
- **Summarization (GenStage pipeline):** Producer emits unsummarized posts and consumer summarizes them with a configured LLM client. On `429` responses, the consumer pauses for 60 seconds and resumes automatically.
- **UI (Phoenix LiveView):** Displays job threads and postings with near real-time updates via PubSub.

## Requirements

- Elixir `~> 1.14`
- Erlang/OTP compatible with your Elixir version
- `mix` / `hex`

If you use `mise`, this project includes `mise.toml` with:

- `elixir = "latest"`
- `erlang = "latest"`

## Environment variables

### Local development

The app loads `config/.env.exs` in `dev` and `test` environments (and this file is gitignored).

At minimum, set:

- `GROQ_API_KEY` (default summarization client)

Optional (only needed if you switch to Gemini client):

- `GEMINI_API_KEY`

Example `config/.env.exs`:

```elixir
System.put_env("GROQ_API_KEY", "your_groq_api_key_here")
# Optional, only if using Gemini:
# System.put_env("GEMINI_API_KEY", "your_gemini_api_key_here")
```

## Setup and run

1. Install dependencies and set up DB/assets:

   ```bash
   mix setup
   ```

2. Start the server:

   ```bash
   mix phx.server
   ```

   Or in IEx:

   ```bash
   iex -S mix phx.server
   ```

3. Open <http://localhost:4000>

## Useful commands

- Run tests:

  ```bash
  mix test
  ```

- Reset DB:

  ```bash
  mix ecto.reset
  ```

- Build assets:

  ```bash
  mix assets.build
  ```

- Build minified assets + digest:

  ```bash
  mix assets.deploy
  ```

## Switching summarization provider

Default provider is configured in `config/config.exs`:

- `job_posting_summary_client: TurboFalcon.Groq.WebApiClient`

To use Gemini instead, change it to:

- `job_posting_summary_client: TurboFalcon.Gemini.WebApiClient`

Then set `GEMINI_API_KEY`.

## Deployment note

There is a VM deployment helper script at `deployment/deploy_vm.sh` that packages, uploads, migrates, builds a release, and restarts the app.
