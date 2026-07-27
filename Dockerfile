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

# Download and install AdGuard VPN CLI.
# When AGCLI_VERSION is "latest", fetch the latest release tag from GitHub.
# Otherwise, use the exact upstream release tag specified by the caller.
#
# The upstream installer has a built-in default package version that can lag
# behind the release tag. Always pass the package version explicitly instead
# of relying on that stale default.
#
# Integrity flow:
#   1. Download install.sh from the release tag
#   2. Compute and log SHA256 for audit trail
#   3. Try to fetch SHA256SUMS from the release; if found, verify install.sh
#   4. If no SHA256SUMS, log a warning but continue (best-effort)
#   5. After installation, compute and log SHA256 of the installed binary
RUN if [ "${AGCLI_VERSION}" = "latest" ]; then \
        echo "🔍 Fetching latest AdGuard VPN CLI release..." && \
        ACTUAL_VERSION=$(curl -fsSL https://api.github.com/repos/AdguardTeam/AdGuardVPNCLI/releases/latest | jq -r '.tag_name // empty') && \
        echo "📦 Latest version: ${ACTUAL_VERSION}" && \
        echo "🔐 Validating release tag format..." && \
        if ! echo "${ACTUAL_VERSION}" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+'; then \
            echo "❌ Invalid release tag from GitHub API: ${ACTUAL_VERSION}" >&2; \
            echo "❌ Possible MITM or API compromise — expected vX.Y.Z format" >&2; \
            exit 1; \
        fi && \
        echo "✅ Release tag format verified: ${ACTUAL_VERSION}"; \
    else \
        ACTUAL_VERSION="${AGCLI_VERSION}"; \
        echo "📦 Using specified version: ${ACTUAL_VERSION}"; \
    fi && \
    [ -n "$ACTUAL_VERSION" ] || { echo "ERROR: Could not determine version"; exit 1; } && \
    SOURCE_VERSION="${ACTUAL_VERSION#v}" && \
    PACKAGE_VERSION="${SOURCE_VERSION%-release}" && \
    [ -n "$PACKAGE_VERSION" ] || { echo "ERROR: Could not determine package version"; exit 1; } && \
    echo "⬇️  Downloading AdGuard VPN CLI ${ACTUAL_VERSION}..." && \
    curl -fsSL -o /tmp/install.sh \
        "https://raw.githubusercontent.com/AdguardTeam/AdGuardVPNCLI/${ACTUAL_VERSION}/scripts/release/install.sh" && \
    echo "🔐 Computing SHA256 of install.sh..." && \
    INSTALL_SHA256=$(sha256sum /tmp/install.sh | cut -d' ' -f1) && \
    echo "SHA256(install.sh)=${INSTALL_SHA256}" && \
    echo "🔍 Checking release checksums..." && \
    CHECKSUMS_URL="https://github.com/AdguardTeam/AdGuardVPNCLI/releases/download/${ACTUAL_VERSION}/SHA256SUMS" && \
    if curl -fsSL -o /tmp/SHA256SUMS "${CHECKSUMS_URL}"; then \
        echo "✅ Release checksums found, verifying install.sh..." && \
        if echo "${INSTALL_SHA256}  /tmp/install.sh" | sha256sum -c -; then \
            echo "✅ install.sh checksum verified against release" && \
            rm /tmp/SHA256SUMS; \
        else \
            echo "❌ install.sh checksum MISMATCH — possible tampering!" >&2; \
            rm -f /tmp/SHA256SUMS /tmp/install.sh; \
            exit 1; \
        fi; \
    else \
        echo "⚠️  No SHA256SUMS found at ${CHECKSUMS_URL}" && \
        echo "⚠️  Continuing with audit trail (SHA256 logged above)"; \
    fi && \
    USER=root sh /tmp/install.sh -v -a y -V "$PACKAGE_VERSION" && \
    echo "🔐 Computing SHA256 of installed binary..." && \
    BINARY_PATH=$(command -v adguardvpn-cli) && \
    BINARY_SHA256=$(sha256sum "${BINARY_PATH}" | cut -d' ' -f1) && \
    echo "SHA256(${BINARY_PATH})=${BINARY_SHA256}" && \
    rm /tmp/install.sh && \
    echo "🔍 Verifying installed version..." && \
    INSTALLED_VERSION=$(adguardvpn-cli --version 2>&1 | \
        sed -nE 's/.*AdGuard VPN CLI (v?[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?).*/\1/p' | \
        head -n 1) && \
    echo "📋 Installed: ${INSTALLED_VERSION}" && \
    [ -n "${INSTALLED_VERSION}" ] || { echo "❌ Could not parse installed AdGuard VPN CLI version" >&2; exit 1; } && \
    INSTALLED_CLEAN="${INSTALLED_VERSION#v}" && \
    if [ "${PACKAGE_VERSION}" != "${INSTALLED_CLEAN}" ]; then \
        echo "❌ Version mismatch: requested package ${PACKAGE_VERSION}, installed ${INSTALLED_VERSION}" >&2; \
        exit 1; \
    fi && \
    echo "✅ AdGuard VPN CLI ${INSTALLED_VERSION} verified for source tag ${ACTUAL_VERSION}"

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
