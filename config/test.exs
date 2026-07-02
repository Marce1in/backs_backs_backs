import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :backs_backs_backs, BacksBacksBacks.Repo,
  database:
    Path.expand(
      "../tmp/backs_backs_backs_test#{System.get_env("MIX_TEST_PARTITION")}.db",
      __DIR__
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :backs_backs_backs, BacksBacksBacksWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "+qYzX+0mkqqa31k9uDxUo8pLq+oPnoIErrvbY58FEPoOL3Otwq/gGdtxlLd7tDPZ",
  server: false

# In test we don't send emails
config :backs_backs_backs, BacksBacksBacks.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :backs_backs_backs, BacksBacksBacks.Auth,
  github_client: BacksBacksBacks.Auth.GitHubClient,
  github_client_id: "test-client-id",
  github_client_secret: "test-client-secret",
  github_callback_url: "http://localhost:4002/auth/github/callback",
  extension_redirect_uris: ["https://extension.test/github"]

config :backs_backs_backs, BacksBacksBacks.TabOrganizer,
  openrouter_client: BacksBacksBacks.TabOrganizer.OpenRouter,
  openrouter_api_key: "test-openrouter-key",
  openrouter_model: "openrouter/test-model",
  scheduler_enabled: false,
  scheduler_interval_ms: 300_000
