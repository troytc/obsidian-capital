FROM rust:latest

# Install build dependencies
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    curl \
    git \
    ca-certificates \
    unzip && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user for running the bot
RUN useradd --system --create-home --shell /bin/bash arbitrage

# Create necessary directories
RUN mkdir -p /opt/arbitrage-bot \
    /etc/arbitrage-bot \
    /var/log/arbitrage-bot \
    /etc/alloy \
    /var/lib/alloy && \
    chown -R arbitrage:arbitrage /opt/arbitrage-bot \
    /etc/arbitrage-bot \
    /var/log/arbitrage-bot \
    /var/lib/alloy

# Clone and build as root first
WORKDIR /tmp/build

# Clone the repository and build
RUN git clone https://github.com/KaboomFox/Polymarket-Kalshi-Arbitrage-bot.git . && \
    rustup update && \
    cargo build --release

# Copy built artifacts to final location
RUN cp target/release/prediction-market-arbitrage /opt/arbitrage-bot/prediction-market-arbitrage && \
    cp kalshi_team_cache.json /opt/arbitrage-bot/ 2>/dev/null || true && \
    chmod +x /opt/arbitrage-bot/prediction-market-arbitrage

# Clean up build directory
RUN rm -rf /tmp/build

# Install Grafana Alloy
RUN ARCH=$(uname -m) && \
    case $ARCH in \
        x86_64) ALLOY_ARCH="amd64" ;; \
        aarch64) ALLOY_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    ALLOY_VERSION="1.4.2" && \
    cd /tmp && \
    curl -LO "https://github.com/grafana/alloy/releases/download/v${ALLOY_VERSION}/alloy-linux-${ALLOY_ARCH}.zip" && \
    unzip -o "alloy-linux-${ALLOY_ARCH}.zip" && \
    mv "alloy-linux-${ALLOY_ARCH}" /usr/local/bin/alloy && \
    chmod +x /usr/local/bin/alloy && \
    rm -f "alloy-linux-${ALLOY_ARCH}.zip"

# Create Alloy configuration
RUN printf '%s\n' \
    '// Grafana Alloy configuration for Arbitrage Bot metrics' \
    '// Scrapes local Prometheus endpoint and pushes to Grafana Cloud' \
    '' \
    'prometheus.scrape "arb_bot" {' \
    '  targets = [{"__address__" = "localhost:9090"}]' \
    '  scrape_interval = "60s"' \
    '  scrape_timeout = "10s"' \
    '  forward_to = [prometheus.remote_write.grafana_cloud.receiver]' \
    '}' \
    '' \
    'prometheus.remote_write "grafana_cloud" {' \
    '  endpoint {' \
    '    url = env("GRAFANA_CLOUD_PROMETHEUS_URL")' \
    '    basic_auth {' \
    '      username = env("GRAFANA_CLOUD_USER")' \
    '      password = env("GRAFANA_CLOUD_API_KEY")' \
    '    }' \
    '  }' \
    '}' \
    > /etc/alloy/config.alloy

# Set working directory
WORKDIR /opt/arbitrage-bot

# Create default config template using printf for better multiline handling
RUN printf '%s\n' \
    '# Bot Configuration' \
    'DRY_RUN=true' \
    'RUST_LOG=info' \
    'LOG_DIR=/var/log/arbitrage-bot' \
    '' \
    '# Discord Alerts (get webhook from Discord Server Settings > Integrations > Webhooks)' \
    'DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK_HERE' \
    '' \
    '# Kalshi API' \
    'KALSHI_API_KEY_ID=your-api-key-id' \
    'KALSHI_PRIVATE_KEY_PATH=/etc/arbitrage-bot/kalshi-key.pem' \
    '' \
    '# Polymarket' \
    'POLY_PRIVATE_KEY=0x_your_private_key_here' \
    'POLY_FUNDER=0x_your_wallet_address_here' \
    '' \
    '# Circuit Breaker (conservative defaults - adjust after testing)' \
    'CB_MAX_POSITION_PER_MARKET=10000' \
    'CB_MAX_TOTAL_POSITION=50000' \
    'CB_MAX_DAILY_LOSS=100.0' \
    'CB_MAX_CONSECUTIVE_ERRORS=5' \
    'CB_COOLDOWN_SECS=300' \
    '' \
    '# Prometheus Metrics' \
    'METRICS_ENABLED=true' \
    'METRICS_PORT=9090' \
    'METRICS_BIND_ADDR=0.0.0.0' \
    '' \
    '# Grafana Cloud (get from https://grafana.com/products/cloud/ -> Stack -> Prometheus -> Details)' \
    'GRAFANA_CLOUD_USER=your-user-id' \
    'GRAFANA_CLOUD_API_KEY=your-api-key' \
    'GRAFANA_CLOUD_PROMETHEUS_URL=https://prometheus-prod-XX-XXXX.grafana.net/api/prom/push' \
    > /etc/arbitrage-bot/config.env

# Create startup script that handles env var to file conversion and starts both services
RUN printf '%s\n' \
    '#!/bin/bash' \
    'set -e' \
    '' \
    '# Convert KALSHI_PRIVATE_KEY_CONTENT env var to file if provided' \
    'if [ ! -z "$KALSHI_PRIVATE_KEY_CONTENT" ]; then' \
    '  echo "$KALSHI_PRIVATE_KEY_CONTENT" > /etc/arbitrage-bot/kalshi-key.pem' \
    '  chmod 600 /etc/arbitrage-bot/kalshi-key.pem' \
    '  echo "Created Kalshi private key file from env var"' \
    'fi' \
    '' \
    '# Start Grafana Alloy in background if Grafana Cloud credentials are configured' \
    'if [ ! -z "$GRAFANA_CLOUD_USER" ] && [ "$GRAFANA_CLOUD_USER" != "your-user-id" ]; then' \
    '  echo "Starting Grafana Alloy..."' \
    '  /usr/local/bin/alloy run /etc/alloy/config.alloy --storage.path=/var/lib/alloy &' \
    '  ALLOY_PID=$!' \
    '  echo "Grafana Alloy started (PID: $ALLOY_PID)"' \
    'else' \
    '  echo "Grafana Cloud not configured, skipping Alloy startup"' \
    'fi' \
    '' \
    '# Run the application' \
    'exec /opt/arbitrage-bot/prediction-market-arbitrage' \
    > /opt/arbitrage-bot/start.sh && \
    chmod +x /opt/arbitrage-bot/start.sh

# Set ownership and permissions
RUN chown -R arbitrage:arbitrage /opt/arbitrage-bot /etc/arbitrage-bot && \
    chmod 600 /etc/arbitrage-bot/config.env

# Verify the binary exists and is executable
RUN ls -la /opt/arbitrage-bot/prediction-market-arbitrage && \
    file /opt/arbitrage-bot/prediction-market-arbitrage

# Switch to non-root user
USER arbitrage

# Expose Prometheus metrics port
EXPOSE 9090

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f prediction-market-arbitrage || exit 1

# Run the startup script instead of the app directly
CMD ["/opt/arbitrage-bot/start.sh"]
