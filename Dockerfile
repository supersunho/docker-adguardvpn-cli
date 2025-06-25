FROM ubuntu:24.04 AS base

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
        curl gpg iproute2 sudo tzdata jq \
        >/dev/null 2>&1 && \
    echo "✅ Base packages installed successfully" && \
    echo "🔒 Updating CA certificates for maximum compatibility..." && \
    apt-get install -qq -y apt-utils ca-certificates && \
    update-ca-certificates && \
    echo "✅ CA certificates updated"

# Download and install AdGuard VPN CLI
RUN curl -fsSL https://raw.githubusercontent.com/AdguardTeam/AdGuardVPNCLI/HEAD/scripts/release/install.sh | sed 's/read -r response < \/dev\/tty/response=y/' | sh -s -- -v

WORKDIR /opt/adguardvpn_cli
COPY --chmod=755 ./scripts/*.sh ./scripts/

EXPOSE ${ADGUARD_SOCKS5_PORT}

ENTRYPOINT ["sh", "-c", "/opt/adguardvpn_cli/scripts/docker-entrypoint.sh"]
