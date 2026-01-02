FROM rust:latest

# Install build dependencies
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    curl \
    git \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user for running the bot
RUN useradd --system --create-home --shell /bin/bash arbitrage

# Create necessary directories
RUN mkdir -p /opt/arbitrage-bot \
    /etc/arbitrage-bot \
    /var/log/arbitrage-bot && \
    chown -R arbitrage:arbitrage /opt/arbitrage-bot \
    /etc/arbitrage-bot \
    /var/log/arbitrage-bot

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

# Setup grafana alloy
RUN scripts/setup-grafana-alloy.sh

# Clean up build directory
RUN rm -rf /tmp/build

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

# Create startup script that handles env var to file conversion
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
