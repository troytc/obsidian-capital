FROM rust:1.75-slim

# Install necessary tools
RUN apt-get update && \
    apt-get install -y curl wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Define the script URL as a build argument so it can be customized
ARG SCRIPT_URL
ENV SCRIPT_URL=${SCRIPT_URL}

# Download the script
RUN if [ -z "$SCRIPT_URL" ]; then \
        echo "Error: SCRIPT_URL must be provided"; \
        exit 1; \
    fi && \
    curl -fsSL "$SCRIPT_URL" -o script.sh && \
    chmod +x script.sh

# Run the script when container starts
CMD ["./script.sh"]
