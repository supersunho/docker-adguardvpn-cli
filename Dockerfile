FROM ubuntu:24.04 AS base

ARG PUID=1000
ARG PGID=1000

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
RUN curl -fsSL -o /tmp/install.sh \
    https://raw.githubusercontent.com/AdguardTeam/AdGuardVPNCLI/master/scripts/release/install.sh && \
    sh /tmp/install.sh -v -a y && \
    rm /tmp/install.sh
# Create non-root user with configurable UID/GID
RUN groupadd -g ${PGID} appuser && \
    useradd -m -u ${PUID} -g appuser -s /bin/bash appuser

# Create data directory structure for appuser
RUN mkdir -p /home/appuser/.local/share/adguardvpn-cli && \
    chown -R appuser:appuser /home/appuser && \
    chown -R appuser:appuser /opt/adguardvpn_cli

WORKDIR /opt/adguardvpn_cli
COPY --chmod=755 ./scripts/*.sh ./scripts/

ENV HOME=/home/appuser

USER appuser

EXPOSE ${ADGUARD_SOCKS5_PORT}

ENTRYPOINT ["/opt/adguardvpn_cli/scripts/docker-entrypoint.sh"]
