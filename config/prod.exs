import Config

# For production, don't forget to configure the url host
# to something meaningful, Phoenix uses this information
# when generating URLs.

# Do not print debug messages in production
config :logger, level: :info

# run the server automatically when using prod release
config :jellyfish, JellyfishWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 8080],
  server: true

config :bundlex, :disable_precompiled_os_deps, apps: [:membrane_h264_ffmpeg_plugin]

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.

config :bundlex, :disable_precompiled_os_deps, apps: [:membrane_h264_ffmpeg_plugin]
