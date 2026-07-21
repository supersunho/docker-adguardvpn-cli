FROM ubuntu:24.04 AS base

ARG PUID=1001
ARG PGID=1001
ARG AGCLI_VERSION=latest

ENV DEBIAN_FRONTEND=noninteractive 

RUN echo "🔍 Setting up Ubuntu 24.04 LTS build environment..." && \
    echo "🏗️ Configuring Ubuntu for maximum compatibility..." && \
    export DEBIAN_FRONTEND=noninteractive && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    echo "⚙️ Configuring APT cache for optimal build performance..." && \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    echo "✅ Ubuntu environment configuration completed"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \ 
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    echo "📦 Installing Ubuntu build packages..." && \
    echo "🔍 Using Ubuntu 24.04 LTS packages for maximum stability..." && \
    apt-get update -qq >/dev/null 2>&1 && \
    echo "📦 Installing development packages..." && \
    apt-get install -qq -y --no-install-recommends  \
        curl gpg iproute2 sudo tzdata jq iputils-ping dnsutils \
        >/dev/null 2>&1 && \
    echo "✅ Base packages installed successfully" && \
    echo "🔒 Updating CA certificates for maximum compatibility..." && \
    apt-get install -qq -y apt-utils ca-certificates && \
    update-ca-certificates && \
    echo "✅ CA certificates updated"

# Download and install AdGuard VPN CLI
# When AGCLI_VERSION is "latest", fetch the latest release tag from GitHub.
# Otherwise, use the exact version specified (with or without 'v' prefix).
RUN if [ "${AGCLI_VERSION}" = "latest" ]; then \
        echo "🔍 Fetching latest AdGuard VPN CLI release..." && \
        ACTUAL_VERSION=$(curl -s https://api.github.com/repos/AdguardTeam/AdGuardVPNCLI/releases/latest | jq -r .tag_name) && \
        echo "📦 Latest version: ${ACTUAL_VERSION}"; \
    else \
        ACTUAL_VERSION="${AGCLI_VERSION}"; \
        echo "📦 Using specified version: ${ACTUAL_VERSION}"; \
    fi && \
    [ -n "$ACTUAL_VERSION" ] || { echo "ERROR: Could not determine version"; exit 1; } && \
    echo "⬇️  Downloading AdGuard VPN CLI ${ACTUAL_VERSION}..." && \
    curl -fsSL -o /tmp/install.sh \
        "https://raw.githubusercontent.com/AdguardTeam/AdGuardVPNCLI/${ACTUAL_VERSION}/scripts/release/install.sh" && \
    USER=root sh /tmp/install.sh -v -a y && \
    rm /tmp/install.sh && \
    echo "🔍 Verifying installed version..." && \
    INSTALLED_VERSION=$(adguardvpn-cli --version 2>/dev/null | head -1) && \
    echo "📋 Installed: ${INSTALLED_VERSION}" && \
    echo "✅ AdGuard VPN CLI installation and version check completed"

# Create non-root user with configurable UID/GID
RUN groupadd -g ${PGID} appuser && \
    useradd -m -u ${PUID} -g appuser -s /bin/bash appuser

# Create data directory structure for appuser
RUN mkdir -p /home/appuser/.local/share/adguardvpn-cli && \
    chown -R appuser:appuser /home/appuser && \
    chown -R appuser:appuser /opt/adguardvpn_cli

# Grant appuser passwordless sudo (required for TUN mode in container)
# adguardvpn-cli internally calls sudo for TUN interface setup; using NOPASSWD:ALL
# is standard for Docker containers where the user already has --cap-add NET_ADMIN.
RUN echo "appuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

WORKDIR /opt/adguardvpn_cli
COPY --chmod=755 ./scripts/ ./scripts/

ENV HOME=/home/appuser

USER appuser

EXPOSE 1080

ENTRYPOINT ["/opt/adguardvpn_cli/scripts/docker-entrypoint.sh"]
