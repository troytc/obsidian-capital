FROM rust:1.75-bookworm

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

# Set working directory
WORKDIR /opt/arbitrage-bot

# Clone the repository
RUN git clone https://github.com/KaboomFox/Polymarket-Kalshi-Arbitrage-bot.git /tmp/bot && \
    mv /tmp/bot/* /opt/arbitrage-bot/ && \
    rm -rf /tmp/bot

# Build the Rust application
RUN cargo build --release && \
    cp target/release/prediction-market-arbitrage /opt/arbitrage-bot/ && \
    cp kalshi_team_cache.json /opt/arbitrage-bot/ 2>/dev/null || true

# Create default config template
RUN echo "# Bot Configuration" > /etc/arbitrage-bot/config.env && \
    echo "DRY_RUN=true" >> /etc/arbitrage-bot/config.env && \
    echo "RUST_LOG=info" >> /etc/arbitrage-bot/config.env && \
    echo "LOG_DIR=/var/log/arbitrage-bot" >> /etc/arbitrage-bot/config.env && \
    echo "" >> /etc/arbitrage-bot/config.env && \
    echo "# Discord Alerts (get webhook from Discord Server Settings > Integrations > Webhooks)" >> /etc/arbitrage-bot/config.env && \
    echo "DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK_HERE" >> /etc/arbitrage-bot/config.env && \
    echo "" >> /etc/arbitrage-bot/config.env && \
    echo "# Kalshi API" >> /etc/arbitrage-bot/config.env && \
    echo "KALSHI_API_KEY_ID=your-api-key-id" >> /etc/arbitrage-bot/config.env && \
    echo "KALSHI_PRIVATE_KEY_PATH=/etc/arbitrage-bot/kalshi-key.pem" >> /etc/arbitrage-bot/config.env && \
    echo "" >> /etc/arbitrage-bot/config.env && \
    echo "# Polymarket" >> /etc/arbitrage-bot/config.env && \
    echo "POLY_PRIVATE_KEY=0x_your_private_key_here" >> /etc/arbitrage-bot/config.env && \
    echo "POLY_FUNDER=0x_your_wallet_address_here" >> /etc/arbitrage-bot/config.env && \
    echo "" >> /etc/arbitrage-bot/config.env && \
    echo "# Circuit Breaker (conservative defaults - adjust after testing)" >> /etc/arbitrage-bot/config.env && \
    echo "CB_MAX_POSITION_PER_MARKET=10000" >> /etc/arbitrage-bot/config.env && \
    echo "CB_MAX_TOTAL_POSITION=50000" >> /etc/arbitrage-bot/config.env && \
    echo "CB_MAX_DAILY_LOSS=100.0" >> /etc/arbitrage-bot/config.env && \
    echo "CB_MAX_CONSECUTIVE_ERRORS=5" >> /etc/arbitrage-bot/config.env && \
    echo "CB_COOLDOWN_SECS=300" >> /etc/arbitrage-bot/config.env && \
    echo "" >> /etc/arbitrage-bot/config.env && \
    echo "# Prometheus Metrics" >> /etc/arbitrage-bot/config.env && \
    echo "METRICS_ENABLED=true" >> /etc/arbitrage-bot/config.env && \
    echo "METRICS_PORT=9090" >> /etc/arbitrage-bot/config.env && \
    echo "METRICS_BIND_ADDR=0.0.0.0" >> /etc/arbitrage-bot/config.env && \
    echo "" >> /etc/arbitrage-bot/config.env && \
    echo "# Grafana Cloud (get from https://grafana.com/products/cloud/ -> Stack -> Prometheus -> Details)" >> /etc/arbitrage-bot/config.env && \
    echo "GRAFANA_CLOUD_USER=your-user-id" >> /etc/arbitrage-bot/config.env && \
    echo "GRAFANA_CLOUD_API_KEY=your-api-key" >> /etc/arbitrage-bot/config.env && \
    echo "GRAFANA_CLOUD_PROMETHEUS_URL=https://prometheus-prod-XX-XXXX.grafana.net/api/prom/push" >> /etc/arbitrage-bot/config.env

# Set ownership and permissions
RUN chown -R arbitrage:arbitrage /opt/arbitrage-bot /etc/arbitrage-bot && \
    chmod 600 /etc/arbitrage-bot/config.env

# Switch to non-root user
USER arbitrage

# Expose Prometheus metrics port
EXPOSE 9090

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f prediction-market-arbitrage || exit 1

# Run the application
CMD ["/opt/arbitrage-bot/prediction-market-arbitrage"]
