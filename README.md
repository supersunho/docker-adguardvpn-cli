<a id="readme-top"></a>

[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]

<div align="center">

<h3 align="center">Docker-AdguardVPN-CLI</h3>

  <p align="center">
    <a href="https://github.com/AdguardTeam/AdGuardVPNCLI">AdGuard VPN CLI</a> within a Docker container
    <br />
    <a href="https://github.com/supersunho/docker-adguardvpn-cli/issues/new?labels=bug&template=bug-report---.md">Report Bug</a>
    &middot;
    <a href="https://github.com/supersunho/docker-adguardvpn-cli/issues/new?labels=enhancement&template=feature-request---.md">Request Feature</a>
  </p>
</div>


## About The Project

A production-ready Docker image that wraps AdGuard VPN CLI with automatic OAuth authentication, a four-state kill-switch for IP leak prevention, and SOCKS5/TUN proxy modes. Designed for:

- **Containerized VPN routing**: Route traffic of other Docker containers (e.g., qBittorrent) through an always-on VPN.
- **Headless VPN operations**: Device-code OAuth flow handles the one-time browser login; subsequent starts require zero interaction.
- **Leak-proof networking**: Active IP monitoring terminates the container on any VPN disconnect, with configurable tolerance and detection intervals.
- **Self-healing**: Transient failures in auth, IP detection, and VPN connection are retried automatically.


<!-- ARCHITECTURE -->

## Architecture

The container runs four cooperating processes under a single entrypoint:

```text
docker-entrypoint.sh
    ├── config_bootstrap()     — Load env vars and validate types
    ├── IP detection            — Discover public IP for kill-switch baseline
    ├── init.sh                 — OAuth login → CLI config → VPN connect
    ├── killswitch.sh           — 4-state monitor (STANDBY→PROTECTED→LEAK_WARNING→TERMINATING)
    │   └── IP poll every 8s    — Verifies VPN IP is still active
    └── supervisor (wait $!)    — Blocks on VPN status check; restarts on failure
```

Key data flows:

- **Auth**: Device-code OAuth URL → user browser → session data persisted in the mounted data storage → reused on restart.
- **Kill switch**: Records real IP before VPN → checks current IP every 8s → if leak detected, increments counter → terminates container at tolerance threshold.
- **SOCKS mode**: `adguardvpn-cli` runs in SOCKS5 mode (port 1080), while IP detection and healthcheck still operate through the tunnel.
- **TUN mode**: `adguardvpn-cli` creates a TUN interface with NET_ADMIN; all container traffic is routed through it.

<!-- GETTING STARTED -->

## Getting Started

The repository's default `docker-compose.yml` uses a bind mount from `./data` on the host to `/home/appuser/.local/share/adguardvpn-cli` in the container. Because the published image runs as UID/GID `1001:1001`, prepare that host directory before the first start:

```bash
mkdir -p data
sudo chown -R 1001:1001 data
cp .env.example .env
docker compose up -d
```

> [!IMPORTANT]
> The published Docker image uses a fixed UID/GID of `1001:1001` for the `appuser`. Changing `PUID` and `PGID` in `.env` does **not** remap the runtime user. These are build-time arguments only — use them only when building a custom image. If the `data` directory is not writable, the container will exit immediately with a `chown` hint.

### Persistence Options

Authentication state, IP detection state, and the optional persistent identity are all stored at `/home/appuser/.local/share/adguardvpn-cli` inside the container. Choose one persistence method and keep it mounted across container recreation:

| Method | Compose mapping | Host setup | Best for |
| --- | --- | --- | --- |
| Bind mount (repository default) | `./data:/home/appuser/.local/share/adguardvpn-cli` | Create `./data` and set ownership to `1001:1001` | Direct host access, backup, and inspection |
| Docker named volume | `adguard-auth:/home/appuser/.local/share/adguardvpn-cli` | No host directory or manual `chown` normally required | Docker-managed storage and a shorter initial setup |

To use a named volume instead of the default bind mount, replace the service's `volumes` entry and declare the volume at the end of the Compose file:

```yaml
services:
    adguard-vpn-cli:
        volumes:
            - adguard-auth:/home/appuser/.local/share/adguardvpn-cli

volumes:
    adguard-auth:
```

With this alternative, the first-start commands are simply:

```bash
cp .env.example .env
docker compose up -d
```

> [!NOTE]
> `docker compose down -v` deletes named volumes declared by the Compose project. It does not delete the host files in a bind-mounted `./data` directory.

### Authentication Setup

> [!IMPORTANT]
> AdGuard VPN CLI uses web-based authentication (OAuth device code flow). You need to perform an initial authentication via browser before the VPN can connect.

1. **First-time Setup**:
    - Start the main container: `docker compose up -d`
    - Check the logs to find the authentication link: `docker logs adguard-vpn-cli`
    - The log will display a message like:
        ```
        OPEN THIS LINK IN YOUR BROWSER:
            https://auth.adguard.io/device_code?user_code=XXXX-XXXX
            Enter the code above to authenticate: XXXX-XXXX
        ```
    - Open the link in your browser and complete authentication
    - Wait a moment for the process to continue automatically
    - **Note**: If Two-Factor Authentication (2FA) is enabled on your account, you may experience issues with this login process.

2. **Persist Authentication**: Keep either the default bind mount or the named-volume alternative from [Persistence Options](#persistence-options). Do not switch or remove the mounted storage unless you intend to authenticate again.

3. **Subsequent Starts**: After the first browser authentication, restarting or recreating the container with the same mounted storage reuses the existing session and does not require another login. Authentication may still be required if the session expires, is revoked, or the persisted data is removed.

If authentication fails three consecutive times, the persisted AdGuard data is reset and the browser flow is requested again. Adjust `ADGUARD_AUTH_RESET_AFTER_FAILURES` if needed.

<!-- USAGE EXAMPLES -->

## How to use

AdguardVPN-CLI + qBittorrent

```yml
services:
    adguard-vpn-cli:
        image: supersunho/adguardvpn-cli:latest
        restart: unless-stopped
        container_name: adguard-vpn-cli
        env_file: .env
        volumes:
            - ./data:/home/appuser/.local/share/adguardvpn-cli
        healthcheck:
            test: ["CMD", "/opt/adguardvpn_cli/scripts/healthcheck.sh"]
            interval: 1m
            timeout: 15s
            retries: 5
            start_period: 5m
        cap_add:
            - NET_ADMIN
        devices:
            - /dev/net/tun
        ports:
            - "127.0.0.1:1080:1080"
            - "127.0.0.1:6089:6089"
            - "6881:6881"
            - "6881:6881/udp"
        deploy:
            resources:
                limits:
                    memory: 512M
                    cpus: "1.0"
    qbittorrent:
        image: linuxserver/qbittorrent:latest
        container_name: qbittorrent
        environment:
            - PUID=0
            - PGID=0
            - TZ=Asia/Seoul
        volumes:
            - ./config:/config
            - ./downloads:/downloads
        devices:
            - /dev/fuse:/dev/fuse:rwm
        cap_add:
            - SYS_ADMIN
        depends_on:
            - adguard-vpn-cli
        network_mode: service:adguard-vpn-cli
```

This example follows the repository default and uses the `./data` bind mount. Complete the [Getting Started](#getting-started) directory setup first. If you prefer Docker-managed storage, use the named-volume mapping described in [Persistence Options](#persistence-options) instead.

> A sidecar with `network_mode: service:adguard-vpn-cli` automatically shares the VPN container's network namespace, including its effective MAC. This is a Docker networking guarantee, not an identity-feature contract — see [Verified scope](#verified-scope) below.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Prerequisites

| Variable | Description | Default | Allowed values |
| --- | --- | --- | --- |
| **Connection** | | | |
| `ADGUARD_CONNECTION_LOCATION` | VPN server location code | `JP` | e.g. `JP`, `US`, `SG`, `NL` |
| `ADGUARD_CONNECTION_TYPE` | VPN operating mode | `TUN` | `TUN` / `SOCKS` |
| `ADGUARD_PROTOCOL` | VPN protocol | `auto` | `auto` / `TCP` / `QUIC` |
| `ADGUARD_POST_QUANTUM` | Post-quantum encryption | `off` | `on` / `off` |
| `ADGUARD_TUN_ROUTING_MODE` | TUN routing mode | `AUTO` | `AUTO` / `TUN_ONLY` / `PROXY_ONLY` |
| `ADGUARD_BOUND_IF_OVERRIDE` | Override bound network interface (empty = auto) | _(empty)_ | Interface name or empty |
| **Authentication** | | | |
| `ADGUARD_AUTH_TIMEOUT` | Device-code OAuth timeout in seconds | `900` | Positive integer |
| `ADGUARD_AUTH_RESET_AFTER_FAILURES` | Consecutive auth failures before resetting the data directory | `3` | Positive integer |
| **SOCKS proxy** _(when `ADGUARD_CONNECTION_TYPE=SOCKS`)_ | | | |
| `ADGUARD_SOCKS5_USERNAME` | SOCKS5 proxy username | _(empty)_ | |
| `ADGUARD_SOCKS5_PASSWORD` | SOCKS5 proxy password | _(empty)_ | |
| `ADGUARD_SOCKS5_HOST` | SOCKS5 proxy host address | `127.0.0.1` | IPv4 address |
| `ADGUARD_SOCKS5_PORT` | SOCKS5 proxy port | `1080` | Port 1-65535 |
| **Kill switch** | | | |
| `ADGUARD_USE_KILL_SWITCH` | Enable kill switch to prevent IP leaks when VPN drops | `true` | `true` / `false` |
| `ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL` | Kill switch check interval in seconds | `8` | Positive integer |
| `ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL` | Kill switch check interval when `ADGUARD_CONNECTION_TYPE=SOCKS`; leave unset or empty to inherit `ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL` | _(empty)_ | Positive integer |
| `ADGUARD_MAX_LEAK_TOLERANCE` | Number of leak detections before termination (0 = immediate) | `0` | Positive integer |
| `ADGUARD_LEAK_WARNING_ONLY` | Only warn on leaks, do not terminate | `false` | `true` / `false` |
| `ADGUARD_VPN_STARTUP_GRACE_SECONDS` | Seconds allowed for VPN tunnel to establish before supervisor treats not-connected as failure | `30` | Integer 0-600 |
| **IP detection** | | | |
| `ADGUARD_MAX_IP_DETECTION_RETRIES` | Maximum IP detection retry attempts | `3` | Positive integer |
| `ADGUARD_IP_DETECTION_RETRY_DELAY` | Delay in seconds between IP detection retries | `10` | Positive integer |
| **Persistent identity** | | | |
| `ADGUARD_PERSISTENT_IDENTITY` | Persist and reapply the container primary-interface MAC across `docker compose up/down` (auth reset keeps the file; OAuth session is still cleared) | `false` | `true` / `false` |
| **DNS** | | | |
| `ADGUARD_USE_CUSTOM_DNS` | Use a custom DNS server instead of the system default | `true` | `true` / `false` |
| `ADGUARD_CUSTOM_DNS` | Custom DNS server address | `1.1.1.1` | IPv4 or hostname |
| `ADGUARD_SET_SYSTEM_DNS` | Allow AdGuard VPN to change the system DNS configuration | `false` | `true` / `false` |
| **Updates & telemetry** | | | |
| `ADGUARD_AUTO_UPDATE` | Automatically update AdGuard VPN CLI on startup | `false` | `true` / `false` |
| `ADGUARD_UPDATE_CHANNEL` | Update channel | `release` | `release` / `beta` / `dev` |
| `ADGUARD_SEND_REPORTS` | Send crash reports to AdGuard | `false` | `true` / `false` |
| `ADGUARD_TELEMETRY` | Send anonymous telemetry data | `false` | `true` / `false` |
| **Logging & UI** | | | |
| `ADGUARD_SHOW_HINTS` | Show CLI usage hints | `on` | `on` / `off` |
| `ADGUARD_SHOW_NOTIFICATIONS` | Show desktop notifications | `on` | `on` / `off` |
| `ADGUARD_SHOW_LOG` | Master switch for container log output (false = silent, except critical messages like OAuth URL) | `true` | `true` / `false` |
| `ADGUARD_SHOW_LOG_LEVEL` | Container log level filter | `INFO` | `DEBUG` / `INFO` / `WARN` / `ERROR` |
| `ADGUARD_SHOW_SUMMARY` | Show kill switch periodic summary in container logs | `true` | `true` / `false` |
| `ADGUARD_MAX_WAIT_TIME` | Maximum wait time in seconds for the AdGuard VPN log file to appear | `60` | Positive integer |
| **Build-time only** _(not honored at runtime)_ | | | |
| `PUID` | User ID for the container's app user (default avoids conflict with Ubuntu 24.04 built-in `ubuntu` user at 1000) | `1001` | Positive integer (build arg) |
| `PGID` | Group ID for the container's app user | `1001` | Positive integer (build arg) |

> [!IMPORTANT]
>
> - **SOCKS bind safety**: For non-localhost `ADGUARD_SOCKS5_HOST`, set `ADGUARD_SOCKS5_USERNAME` and `ADGUARD_SOCKS5_PASSWORD` to protect the proxy. `0.0.0.0` listens on all container interfaces — it is a bind address, not a destination. Change the host-side port publishing only when remote access is required, and configure authentication plus firewall rules first.
> - **Deprecated auth variables**: `ADGUARD_USERNAME` and `ADGUARD_PASSWORD` are no longer used for authentication since version 1.5.10. Use the web-based OAuth device code flow instead.
> - **`ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL`**: A very short check interval is not recommended.
> - **`ADGUARD_VPN_STARTUP_GRACE_SECONDS`**: Default 30. Set to `0` to restore the legacy immediate-check semantics. Bounded to 0-600.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Location

Please check the location and add the city, country or ISO code to `ADGUARD_CONNECTION_LOCATION`

| ISO | Country        | City           |
| :-- | :------------- | :------------- |
| AE  | UAE            | Dubai          |
| AR  | Argentina      | Buenos Aires   |
| AT  | Austria        | Vienna         |
| AU  | Australia      | Sydney         |
| BE  | Belgium        | Brussels       |
| BG  | Bulgaria       | Sofia          |
| BR  | Brazil         | São Paulo      |
| CA  | Canada         | Vancouver      |
| CA  | Canada         | Montreal       |
| CA  | Canada         | Toronto        |
| CH  | Switzerland    | Zurich         |
| CL  | Chile          | Santiago       |
| CN  | China          | Shanghai       |
| CO  | Colombia       | Bogota         |
| CY  | Cyprus         | Nicosia        |
| CZ  | Czechia        | Prague         |
| DE  | Germany        | Berlin         |
| DE  | Germany        | Frankfurt      |
| DK  | Denmark        | Copenhagen     |
| EE  | Estonia        | Tallinn        |
| EG  | Egypt          | Cairo          |
| ES  | Spain          | Barcelona      |
| ES  | Spain          | Madrid         |
| FI  | Finland        | Helsinki       |
| FR  | France         | Paris          |
| FR  | France         | Marseille      |
| GB  | United Kingdom | Manchester     |
| GB  | United Kingdom | London         |
| GR  | Greece         | Athens         |
| HK  | Hong Kong      | Hong Kong      |
| HR  | Croatia        | Zagreb         |
| HU  | Hungary        | Budapest       |
| ID  | Indonesia      | Jakarta        |
| IE  | Ireland        | Dublin         |
| IL  | Israel         | Tel Aviv       |
| IN  | India          | Mumbai         |
| IR  | Iran           | Tehran         |
| IS  | Iceland        | Reykjavik      |
| IT  | Italy          | Rome           |
| IT  | Italy          | Milan          |
| IT  | Italy          | Palermo        |
| JP  | Japan          | Tokyo          |
| KH  | Cambodia       | Phnom Penh     |
| KR  | South Korea    | Seoul          |
| KZ  | Kazakhstan     | Astana         |
| LT  | Lithuania      | Vilnius        |
| LU  | Luxembourg     | Luxembourg     |
| LV  | Latvia         | Riga           |
| MD  | Moldova        | Chișinău       |
| MX  | Mexico         | Mexico City    |
| NG  | Nigeria        | Lagos          |
| NL  | Netherlands    | Amsterdam      |
| NO  | Norway         | Oslo           |
| NP  | Nepal          | Kathmandu      |
| NZ  | New Zealand    | Auckland       |
| PE  | Peru           | Lima           |
| PH  | Philippines    | Manila         |
| PL  | Poland         | Warsaw         |
| PT  | Portugal       | Lisbon         |
| RO  | Romania        | Bucharest      |
| RS  | Serbia         | Belgrade       |
| RU  | Russia         | Moscow         |
| SE  | Sweden         | Stockholm      |
| SG  | Singapore      | Singapore      |
| SK  | Slovakia       | Bratislava     |
| TH  | Thailand       | Bangkok        |
| TR  | Turkey         | Istanbul       |
| TW  | Taiwan         | Taipei         |
| UA  | Ukraine        | Kyiv           |
| US  | United States  | Seattle        |
| US  | United States  | Silicon Valley |
| US  | United States  | Phoenix        |
| US  | United States  | Las Vegas      |
| US  | United States  | Denver         |
| US  | United States  | Dallas         |
| US  | United States  | Los Angeles    |
| US  | United States  | Atlanta        |
| US  | United States  | New York       |
| US  | United States  | Miami          |
| US  | United States  | Boston         |
| US  | United States  | Chicago        |
| VN  | Vietnam        | Hanoi          |
| ZA  | South Africa   | Johannesburg   |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- PERSISTENT IDENTITY -->

## Persistent Container Identity

`ADGUARD_PERSISTENT_IDENTITY` is an opt-in feature that reapplies the container's in-namespace primary-interface effective MAC across `docker compose up/down`. Without it, the interface MAC that Docker assigns at container creation can rotate on every recreate, which AdGuard's server-side fingerprinting may detect and require a browser re-authentication. Note that this only addresses the in-namespace MAC — Docker's per-endpoint MAC metadata (visible via `docker inspect`) is set at container creation and is not part of the guarantee; see [Verified scope](README.md#persistent-container-identity) below.

### Enabling

Add to `.env`:

```dotenv
ADGUARD_PERSISTENT_IDENTITY=true
```

Behavior:

- On first boot, the entrypoint generates a locally administered unicast MAC from `/dev/urandom`, writes it to `<DATA_DIR>/identity/mac` (mode 0600 inside a 0700 directory), and applies it to the default-route interface via `sudo -n ip link set`.
- On every subsequent boot, the entrypoint re-reads the file, applies the stored MAC, and verifies the post-apply effective MAC matches. A mismatch or `ip link set` failure is **fail-closed** with exit 78 before any OAuth/CLI side effect.
- If a previous AdGuard session (`active/`, `cli-home/`, OAuth data) is already present in the data volume, the current interface MAC is reused (smart-reuse). This prevents the first opt-in rotation but **does not guarantee** that the previous container's MAC or the OAuth session's server-side identity is preserved — the upstream AdGuard server may still treat the new install as a new device.
- Auth-reset (`_reset_auth_data`) clears OAuth/CLI state but preserves `<DATA_DIR>/identity/`, so the MAC survives an auth failure. Browser re-authentication is still required.

### Verifying

Inside the running container:

```bash
cat /home/appuser/.local/share/adguardvpn-cli/identity/mac
ip -br link show eth0   # link/ether should match the file
```

### Manual rotation

To deliberately rotate the in-namespace effective MAC (this may cause the upstream AdGuard server to require re-authentication), stop the service and remove the identity file from the persistence method you selected.

For the default `./data` bind mount:

```bash
docker compose stop adguard-vpn-cli
rm -f ./data/identity/mac
docker compose up -d
```

For the named-volume alternative:

```bash
docker compose stop adguard-vpn-cli
docker compose run --rm --no-deps --entrypoint rm adguard-vpn-cli \
    -f /home/appuser/.local/share/adguardvpn-cli/identity/mac
docker compose up -d
```

### Requirements and limits

- Requires the image's `appuser ALL=(root) NOPASSWD: ALL` rule (installed by the Dockerfile) and `NET_ADMIN` capability (default in `docker-compose.yml`).
- Hardened SOCKS deployments that drop `NET_ADMIN` will fail closed (exit 78) when this option is enabled. Plain SOCKS without `NET_ADMIN` continues to work, but only with `ADGUARD_PERSISTENT_IDENTITY=false`.
- Each VPN container must have its **own** bind directory or named volume. Multiple containers sharing the same persistence storage will collide on the same identity file and the same first-boot write race; that configuration is not supported.
- `network_mode: service:adguard-vpn-cli` (the qBittorrent-in-shared-namespace pattern in `How to use`) automatically inherits the VPN container's MAC — no extra configuration needed.
- **Not supported** in `network_mode: host`, macvlan, Docker Desktop (without privileged Linux VM), or rootless Docker. The default `docker-compose.yml` is the only verified target.

### Verified scope

The guarantee covers the container's **network namespace effective MAC** (`ip link show <iface>`). Docker's per-endpoint MAC metadata (`docker inspect`) may diverge and is not part of the contract — always compare the in-namespace `ip link` value to `/home/appuser/.local/share/adguardvpn-cli/identity/mac`, not `docker inspect` output.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- TROUBLESHOOTING -->

## Troubleshooting

### OAuth authentication fails or times out

The container uses a device-code OAuth flow. On first start, a URL and code are printed to the logs:

```text
OPEN THIS LINK IN YOUR BROWSER:
    https://auth.adguard.io/device_code?user_code=XXXX-XXXX
    Enter the code above to authenticate: XXXX-XXXX
```

- The link expires after **15 minutes** (configurable via `ADGUARD_AUTH_TIMEOUT`).
- If you miss the window, the container exits and restarts automatically — look for the new URL in the logs after restart.
- If authentication repeatedly fails (`ADGUARD_AUTH_RESET_AFTER_FAILURES` consecutive failures, default 3), the data directory is reset and a new OAuth flow begins.
- To force a fresh authentication, stop the container and remove its persisted data. Delete `./data` when using the default bind mount, or run `docker compose down -v` when using the named-volume alternative, then start the service again.

### "Data directory is not writable" error

The container runs as a non-root user (default UID 1001). If the bind-mounted data directory on the host is owned by a different user (e.g., root), the container cannot write to it:

```text
ERROR: Data directory is not writable: /home/appuser/.local/share/adguardvpn-cli
ERROR: Run: sudo chown -R 1001:1001 ./data
```

For the default bind mount, run `sudo chown -R 1001:1001 ./data`. Adjust the UID/GID only if you built a custom image with different `PUID`/`PGID` build arguments. A newly created named volume normally inherits the image directory's ownership and does not need this host-side fix.

### Kill switch terminates the container unexpectedly

The kill switch monitors VPN status and terminates the container on IP leaks. Common causes:

- **Network instability**: DNS or HTTP IP-detection failures trigger termination. Increase `ADGUARD_MAX_IP_DETECTION_RETRIES` or `ADGUARD_IP_DETECTION_RETRY_DELAY` if you have an unreliable network.
- **High latency connections**: The kill switch check interval (default 8s) may be too fast for some VPN endpoints. Increase `ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL`.
- **False positive leak detection**: If the VPN IP and real IP share the same upstream, disable the kill switch (`ADGUARD_USE_KILL_SWITCH=false`).

### Container enters a restart loop

- Check the container logs: `docker compose logs`.
- Common causes:
  1. **Missing capabilities**: Ensure `--cap-add NET_ADMIN` and `/dev/net/tun` device are mapped.
  2. **OAuth not completed**: First start requires browser authentication within the timeout.
  3. **Network not ready**: IP detection at startup may fail if the Docker bridge is not yet available.
  4. **Config validation error**: Check for `ADGUARD_*` environment variable syntax errors.
  5. **Bug**: If none of the above apply, open an [issue](https://github.com/supersunho/docker-adguardvpn-cli/issues).

- **Contact support**: For non-this-project-specific AdGuard VPN help, see the upstream project.

### SOCKS proxy is not working

- Verify `ADGUARD_CONNECTION_TYPE=SOCKS` is set in `.env`.
- If the SOCKS proxy is publicly exposed, set `ADGUARD_SOCKS5_USERNAME` and `ADGUARD_SOCKS5_PASSWORD` to enable authentication.
- The SOCKS listener binds to `127.0.0.1:1080` by default. Use `ADGUARD_SOCKS5_HOST=0.0.0.0` to listen on all interfaces (requires Docker port publishing).

### Ports 1080 / 6089 / 6881 — what are these?

- **1080**: SOCKS5 proxy port (when `ADGUARD_CONNECTION_TYPE=SOCKS`).
- **6089**: AdGuard VPN CLI internal API / DNS proxy port. Used for DNS filtering features.
- **6881 (TCP+UDP)**: BitTorrent DHT / peer port. Included for qBittorrent integration in the compose example. Bind to localhost on the host side if not using BitTorrent: `127.0.0.1:6881:6881`.

### Updating

To update to the latest image:

```bash
docker compose pull && docker compose up -d
```

This pulls the latest tagged image and recreates the container if the image changed.

### Verifying VPN Protection

To confirm the VPN tunnel is active and your traffic is routed through it:

1. **Check VPN status**:
   ```bash
   docker compose exec adguard-vpn-cli adguardvpn-cli status
   ```
   Look for `Connected` in the output.

2. **Compare public IP with and without the VPN**:
   ```bash
   # From inside the container (through the VPN)
   docker compose exec adguard-vpn-cli curl -4 -s ifconfig.me

   # From the host directly (without the VPN)
   curl -4 -s ifconfig.me
   ```
   The two IPs should differ — matching output means the VPN tunnel is not routing traffic.

3. **Verify kill switch behavior**:
   ```bash
   docker compose exec adguard-vpn-cli adguardvpn-cli disconnect
   ```
   The kill switch should detect the leak and terminate the container within the configured check interval.

### SOCKS mode IP detection

When `ADGUARD_CONNECTION_TYPE=SOCKS`, the kill switch probes the public IP through the SOCKS5 proxy on every check so it can tell a real leak apart from the listener staying open. The probe pool is a small set of public IP-echo services:

- `aws` — `https://checkip.amazonaws.com`
- `ipify` — `https://api.ipify.org`
- `ipinfo` — `https://ipinfo.io/ip`
- `ifconfig` — `https://ifconfig.co/ip`
- `ident` — `https://ident.me`

The first call picks a working service in fixed order, locks to it for the lifetime of the kill switch process, and re-discovers only when that service fails. The kill switch monitoring path (`ks_detect_ip_consistent`) always uses HTTP for both TUN and SOCKS modes — DNS would bypass the proxy in SOCKS mode and can return a different IP than tunneled HTTP traffic in TUN mode, so DNS is reserved for the one-shot initial IP discovery (`get_public_ip`) which has a separate, larger pool of four DNS resolvers.

> [!IMPORTANT]
> In SOCKS mode the kill switch treats the proxy as down whenever all five services are unreachable on a given check and **terminates the container** — it cannot distinguish a tunnel failure from a transient external outage. To reduce how often the kill switch calls out, raise `ADGUARD_USE_KILL_SWITCH_SOCKS_CHECK_INTERVAL` (for example, `15` or `30`). Unset or invalid values fall back to `ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL`.

<!-- SECURITY CONSIDERATIONS -->

## Security Considerations

### NOPASSWD sudo for appuser

The Dockerfile grants `appuser` passwordless sudo (`NOPASSWD:ALL`). This is required by `adguardvpn-cli` for TUN interface setup in containers. While this is standard practice for single-purpose containers where `NET_ADMIN` is already granted, be aware that any process running inside the container has effective root-equivalent access.

### curl | sh installation pattern

The Dockerfile fetches and executes an upstream install script directly from GitHub. This is inherent to the current AdGuard VPN CLI distribution model. Mitigations include:

- SHA256 computation and logging of both `install.sh` and the installed binary for audit trail.
- Fail-closed verification against the GitHub Release API's `install.sh` asset digest. The build fails when the digest is unavailable or mismatched.
- Validation of the GitHub API release tag against a semver pattern (`^vX.Y.Z`) to catch anomalous responses.

### Exposed ports in production

The default `docker-compose.yml` binds `1080` and `6089` to localhost only. If remote access is required, change the host-side binding explicitly and configure SOCKS5 authentication and firewall restrictions before deployment.

Do **not** expose port `6089` to the public internet — it is an internal API and DNS proxy port used by AdGuard VPN CLI for DNS filtering configuration and health checking.

### Build context sensitivity

The `.dockerignore` file excludes `.env` and `.env.example` from the build context. Verify your `.dockerignore` is present if you rebuild the image, or your environment file may leak into the image layers.


## References

- [AdguardTeam/AdGuardVPNCLI](https://github.com/AdguardTeam/AdGuardVPNCLI)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

[forks-shield]: https://img.shields.io/github/forks/supersunho/docker-adguardvpn-cli.svg?style=for-the-badge
[forks-url]: https://github.com/supersunho/docker-adguardvpn-cli/network/members
[stars-shield]: https://img.shields.io/github/stars/supersunho/docker-adguardvpn-cli.svg?style=for-the-badge
[stars-url]: https://github.com/supersunho/docker-adguardvpn-cli/stargazers
