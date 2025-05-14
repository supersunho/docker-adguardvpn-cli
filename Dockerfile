# Use a lightweight Linux base image
FROM debian:bullseye-slim

# Set environment variables for non-interactive installation
ENV DEBIAN_FRONTEND=noninteractive \
    USER=root

# Install necessary dependencies
RUN apt-get update && apt-get install -y \
    curl \
    gpg \
    ca-certificates \
    iproute2 \
    --no-install-recommends && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /dev/net && \
    mknod /dev/net/tun c 10 200 && \
    chmod 600 /dev/net/tun && \
    mkdir /opt/adguardvpn_cli

# Download and install AdGuard VPN CLI
RUN curl -fsSL https://raw.githubusercontent.com/AdguardTeam/AdGuardVPNCLI/HEAD/scripts/release/install.sh | sed 's/read -r response < \/dev\/tty/response=y/' | sh -s -- -v

# Set environment variables
ENV ADGUARD_USERNAME="username" \
    ADGUARD_PASSWORD="password" \
    ADGUARD_CONNECTION_LOCATION="JP" \
    ADGUARD_CONNECTION_TYPE="TUN" \
    ADGUARD_SOCKS5_USERNAME="username" \
    ADGUARD_SOCKS5_PASSWORD="password" \
    ADGUARD_SOCKS5_HOST="127.0.0.1" \
    ADGUARD_SOCKS5_PORT=1080 \
    ADGUARD_SEND_REPORTS=false \
    ADGUARD_SET_SYSTEM_DNS=false \
    ADGUARD_USE_CUSTOM_DNS=true \
    ADGUARD_CUSTOM_DNS="1.1.1.1" \
    ADGUARD_USE_QUIC=true

WORKDIR /app
COPY --chmod=755 ./scripts/*.sh /app/scripts/

EXPOSE ${ADGUARD_SOCKS5_PORT}

ENTRYPOINT ["sh", "-c", "/app/scripts/docker-entrypoint.sh"]
