# Turbo Falcon

Turbo Falcon is a Phoenix + LiveView app that aggregates Hacker News “Who is hiring?” posts, stores them in PostgreSQL, and summarizes postings for faster browsing.

## How it works

- **Thread ingestion (Quantum scheduler):** Runs every 30 minutes, fetches recent HN submissions for `whoishiring`, detects “Ask HN: Who is hiring?” threads, and upserts new/changed postings.
- **Summarization (GenStage pipeline):** Producer emits unsummarized posts and consumer summarizes them with a configured LLM client. On `429` responses, the consumer pauses for 60 seconds and resumes automatically.
- **UI (Phoenix LiveView):** Displays job threads and postings with near real-time updates via PubSub.

## Requirements

- Elixir `~> 1.14`
- Erlang/OTP compatible with your Elixir version
- `mix` / `hex`
- `dbmate` (installed by `mise`)
- A PostgreSQL database. Locally, use the platform CloudNativePG instance:
  a local PostgreSQL 18 instance on `127.0.0.1:5432`

If you use `mise`, this project includes `mise.toml` with:

- `elixir = "1.20.4"`
- `erlang = "29.1.2"`
- `dbmate = "2.37.0"`
- `postgres = "18.6"` (provides `pg_dump`, which dbmate uses for `db/schema.sql`)

## Environment variables

### Local development

The app loads `config/.env.exs` in `dev` and `test` environments (and this file is gitignored).

At minimum, set:

- `DATABASE_URL` — PostgreSQL connection string for the `turbo_falcon` database
- `GROQ_API_KEY` (default summarization client)

Optional (only needed if you switch to Gemini client):

- `GEMINI_API_KEY`

Example `config/.env.exs`:

```elixir
System.put_env(
  "DATABASE_URL",
  "postgresql://turbo_falcon:PASSWORD@localhost:55432/turbo_falcon"
)

System.put_env("GROQ_API_KEY", "your_groq_api_key_here")
# Optional, only if using Gemini:
# System.put_env("GEMINI_API_KEY", "your_gemini_api_key_here")
```

The app has its own `turbo_falcon` PostgreSQL role and database in the platform
Postgres instance. The role cannot create databases or connect to any other
database.

Tests use a dedicated `turbo_falcon_test` database. Set `TEST_DATABASE_URL` to
override the derived URL. `mix test` applies pending migrations and then uses
the Ecto SQL sandbox, so each test rolls back and the schema is reused.

## Setup and run

1. Provision the app's database and role in your local Postgres (once), then run
   `mix setup` and `mix db.migrate`.

2. Install dependencies, migrate, and build assets:

   ```bash
   mix setup
   ```

3. Start the server:

   ```bash
   mix phx.server
   ```

   Or in IEx:

   ```bash
   iex -S mix phx.server
   ```

4. Open <http://localhost:4000>

## Useful commands

- Run tests:

  ```bash
  mix test
  ```

- Apply migrations:

  ```bash
  mix db.migrate
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

## Deployment

```sh
./deployment/deploy_ovh.sh
```

The deployment runs the compose `migrate` one-shot before the app starts, so a
failed migration does not start the app against an outdated schema.
