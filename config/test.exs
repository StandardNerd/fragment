import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :fragment, Fragment.Repo,
  database: Path.expand("../fragment_test.db", __DIR__),
  pool_size: 5,
  busy_timeout: 5000,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :fragment, FragmentWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "jp0STPbNJ22GJ+F42Cov3K1OJzO5igcYRFQRw03WiTtfE0p5DNAGwBoMSpiuJUGQ",
  server: false

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

config :fragment, Fragment.Pastes.ExpirationWorker, enabled: false

config :fragment, Fragment.RateLimiter,
  limit: 1000,
  window_ms: 60_000
