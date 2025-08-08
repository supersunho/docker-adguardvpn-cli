
<!-- Improved compatibility of back to top link -->
<a id="readme-top"></a>

<!-- PROJECT SHIELDS -->
[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![Docker Pulls][dockerhub-shield]][dockerhub-url] 

<!-- PROJECT LOGO -->
<br />
<div align="center">
  <h3 align="center">🚀 Docker AdGuard VPN CLI</h3>
  <p align="center">
    Multi-architecture <a href="https://github.com/AdguardTeam/AdGuardVPNCLI">AdGuard VPN CLI</a> in Docker containers
    <br />
    <strong>Universal compatibility • Automated builds • Production ready</strong>
    <br />
    <br />
    <a href="https://github.com/supersunho/docker-adguardvpn-cli/issues/new?labels=bug&template=bug-report---.md">Report Bug</a>
    ·
    <a href="https://github.com/supersunho/docker-adguardvpn-cli/issues/new?labels=enhancement&template=feature-request---.md">Request Feature</a>
  </p>
</div>

<!-- ABOUT THE PROJECT -->
## 🌟 About The Project

This project provides **AdGuard VPN CLI** in Docker containers with **universal multi-architecture support**. Built with automated CI/CD pipelines, it offers seamless VPN connectivity across all major platforms in a containerized environment.

### ✨ Key Features

- 🏗️ **Multi-Architecture Support**: Native builds for `amd64`, `arm64`, and `armv7`
- 🤖 **Automated Builds**: Daily builds tracking latest AdGuard VPN CLI releases
- 🐳 **Dual Registry**: Available on both Docker Hub and GitHub Container Registry
- 🔒 **Kill Switch**: Built-in network protection when VPN disconnects
- 🌐 **SOCKS5 Proxy**: Optional proxy server functionality
- ⚡ **Production Ready**: Optimized for performance and reliability

### 🏗️ Built With

- **Base**: Ubuntu 24.04 LTS for maximum compatibility
- **Build System**: Docker Buildx with GitHub Actions
- **Architecture**: Multi-stage builds with optimized caching
- **Security**: Non-root execution and health checks

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- GETTING STARTED -->
## 🚀 Getting Started

### Quick Start (Universal)

**One command works on any architecture:**

```bash
# Pull the latest image (auto-detects your architecture)
docker pull supersunho/adguardvpn-cli:latest

# Run with environment variables
docker run -d \
  --name adguard-vpn \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  -e ADGUARD_USERNAME="your_username" \
  -e ADGUARD_PASSWORD="your_password" \
  -e ADGUARD_CONNECTION_LOCATION="US" \
  supersunho/adguardvpn-cli:latest
```

### 🐳 Available Images

#### Docker Hub (Recommended)
```bash
# Universal images (auto-detect architecture)
supersunho/adguardvpn-cli:latest                   # Latest version
supersunho/adguardvpn-cli:1.2.37                   # Specific version

# Architecture-specific images
supersunho/adguardvpn-cli:latest-amd64              # Intel/AMD (x86_64)
supersunho/adguardvpn-cli:latest-arm64              # Apple Silicon/ARM64
supersunho/adguardvpn-cli:latest-armv7              # Raspberry Pi/ARMv7
```

#### GitHub Container Registry (Alternative)
```bash
# Universal images
ghcr.io/supersunho/docker-adguardvpn-cli:latest     # Latest version
ghcr.io/supersunho/docker-adguardvpn-cli:1.2.37     # Specific version

# Architecture-specific images
ghcr.io/supersunho/docker-adguardvpn-cli:latest-amd64
ghcr.io/supersunho/docker-adguardvpn-cli:latest-arm64
ghcr.io/supersunho/docker-adguardvpn-cli:latest-armv7
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- USAGE EXAMPLES -->
## 💡 Usage Examples

<<<<<<< HEAD
| Variable                               | Description                                                                                                                                      | Default value | Allow values             |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------- | ------------------------ |
| ADGUARD_USERNAME                       | Username for login                                                                                                                               | "username"    |                          |
| ADGUARD_PASSWORD                       | Password for login                                                                                                                               | "password"    |                          |
| ADGUARD_CONNECTION_LOCATION            | Defaults to the last used location                                                                                                               | "JP"          |                          |
| ADGUARD_CONNECTION_TYPE                | Set VPN operating mode                                                                                                                           | "TUN"         | TUN / SOCKS5             |
| ADGUARD_SOCKS5_USERNAME                | Set the SOCKS username                                                                                                                           | "username"    |                          |
| ADGUARD_SOCKS5_PASSWORD                | Set the SOCKS password                                                                                                                           | "password"    |                          |
| ADGUARD_SOCKS5_HOST                    | Set the SOCKS listen host.                                                                                                                       | "127.0.0.1"   |                          |
| ADGUARD_SOCKS5_PORT                    | Set the SOCKS port                                                                                                                               | 1080          |                          |
| ADGUARD_SEND_REPORTS                   | Send crash reports to developers                                                                                                                 | false         | true / false             |
| ADGUARD_SET_SYSTEM_DNS                 | Set the system DNS servers                                                                                                                       | false         | true / false             |
| ADGUARD_USE_CUSTOM_DNS                 | Use the custom DNS servers                                                                                                                       | true          | true / false             |
| ADGUARD_CUSTOM_DNS                     | Set the DNS upstream server                                                                                                                      | "1.1.1.1"     |                          |
| ADGUARD_USE_KILL_SWITCH                | Use the Kill Switch                                                                                                                              | true          | true / false             |
| ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL | Check interval for Kill Switch                                                                                                                   | 30            |                          |
| ADGUARD_UPDATE_CHANNEL                 | Set update channel                                                                                                                               | "release"     | release / beta / nightly |
| ADGUARD_SHOW_HINTS                     | Show hints after command execution                                                                                                               | "on"          | on / off                 |
| ADGUARD_DEBUG_LOGGING                  | Set debug logging                                                                                                                                | "on"          | on / off                 |
| ADGUARD_SHOW_NOTIFICATIONS             | Get notified about the status of the VPN connection                                                                                              | "on"          | on / off                 |
| ADGUARD_PROTOCOL                       | Set the protocol used by AdGuard VPN                                                                                                             | "auto"        | auto / http2 / quic      |
| ADGUARD_POST_QUANTUM                   | Set whether to use advanced cryptographic algorithms resistant to quantum computer attacks to protect your traffic from potential future threats | "off"         | on / off                 |

> [!IMPORTANT] > `ADGUARD_SOCKS5_HOST`: For non-localhost addresses, you need to protect the proxy with a username and password.

> [!IMPORTANT] > `ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL`: A very short check interval is not recommended.
=======
### AdGuard VPN CLI + qBittorrent

Create a `.env` file with your credentials (see [Environment Variables](#-environment-variables)):

```bash
ADGUARD_USERNAME=your_username
ADGUARD_PASSWORD=your_password
ADGUARD_CONNECTION_LOCATION=US
ADGUARD_CONNECTION_TYPE=TUN
ADGUARD_USE_KILL_SWITCH=true
```

Then use this `docker-compose.yml`:

```bash
version: "3.8"
services:
  adguard-vpn-cli:
    image: supersunho/adguardvpn-cli:latest
  container_name: adguard-vpn-cli
  restart: unless-stopped
  env_file: .env
  cap_add:
    - NET_ADMIN
  devices:
    - /dev/net/tun
  ports:
    - "6089:6089"       # qBittorrent WebUI
    - "6881:6881"       # BitTorrent TCP
    - "6881:6881/udp"   # BitTorrent UDP
  healthcheck:
    test: ["CMD", "ping", "-c", "1", "www.google.com"]
  interval: 60s
  timeout: 10s
  retries: 3

qbittorrent:
  image: linuxserver/qbittorrent:latest
  container_name: qbittorrent
  depends_on:
    - adguard-vpn-cli
  network_mode: service:adguard-vpn-cli
  environment:
    - PUID=1000
    - PGID=1000
    - TZ=Asia/Seoul
  volumes:
    - ./config:/config
    - ./downloads:/downloads
  restart: unless-stopped
```

### Standalone VPN with SOCKS5 Proxy

```bash
version: "3.8"
services:
  adguard-vpn:
  image: supersunho/adguardvpn-cli:latest
  container_name: adguard-vpn
  restart: unless-stopped
  cap_add:
    - NET_ADMIN
  devices:
    - /dev/net/tun
  ports:
    - "1080:1080"       # SOCKS5 proxy
  environment:
    - ADGUARD_USERNAME=your_username
    - ADGUARD_PASSWORD=your_password
    - ADGUARD_CONNECTION_LOCATION=JP
    - ADGUARD_CONNECTION_TYPE=SOCKS5
    - ADGUARD_SOCKS5_HOST=0.0.0.0
    - ADGUARD_SOCKS5_PORT=1080
    - ADGUARD_USE_KILL_SWITCH=true

```
>>>>>>> 304d5e53e4ab17992bd94ad1fff7465ee1d8920a

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONFIGURATION -->
## ⚙️ Environment Variables

### 🔐 Authentication (Required)

<<<<<<< HEAD
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
=======
| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `ADGUARD_USERNAME` | Your AdGuard VPN username | `"username"` | `"john.doe@example.com"` |
| `ADGUARD_PASSWORD` | Your AdGuard VPN password | `"password"` | `"your_secure_password"` |

### 🌍 Connection Settings

| Variable | Description | Default | Allowed Values |
|----------|-------------|---------|----------------|
| `ADGUARD_CONNECTION_LOCATION` | VPN server location | `"JP"` | See [Available Locations](#-available-locations) |
| `ADGUARD_CONNECTION_TYPE` | VPN operating mode | `"TUN"` | `TUN` / `SOCKS5` |

### 🔒 SOCKS5 Proxy Settings

| Variable | Description | Default | Notes |
|----------|-------------|---------|-------|
| `ADGUARD_SOCKS5_USERNAME` | SOCKS5 proxy username | `"username"` | Required for non-localhost access |
| `ADGUARD_SOCKS5_PASSWORD` | SOCKS5 proxy password | `"password"` | Required for non-localhost access |
| `ADGUARD_SOCKS5_HOST` | SOCKS5 listen address | `"127.0.0.1"` | Use `0.0.0.0` for external access |
| `ADGUARD_SOCKS5_PORT` | SOCKS5 listen port | `1080` | Any available port |

### 🛡️ Security & Network

| Variable | Description | Default | Allowed Values |
|----------|-------------|---------|----------------|
| `ADGUARD_USE_KILL_SWITCH` | Enable kill switch protection | `true` | `true` / `false` |
| `ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL` | Kill switch check interval (seconds) | `30` | `10` or higher recommended |
| `ADGUARD_SET_SYSTEM_DNS` | Set system DNS servers | `false` | `true` / `false` |
| `ADGUARD_USE_CUSTOM_DNS` | Use custom DNS servers | `true` | `true` / `false` |
| `ADGUARD_CUSTOM_DNS` | Custom DNS server | `"1.1.1.1"` | Any valid DNS server |

### 📊 Advanced Settings

| Variable | Description | Default | Allowed Values |
|----------|-------------|---------|----------------|
| `ADGUARD_USE_QUIC` | Enable QUIC protocol | `true` | `true` / `false` |
| `ADGUARD_SEND_REPORTS` | Send crash reports | `false` | `true` / `false` |

> [!IMPORTANT]
> **SOCKS5 Security**: When setting `ADGUARD_SOCKS5_HOST` to non-localhost addresses (e.g., `0.0.0.0`), always protect the proxy with username and password authentication.

> [!TIP]
> **Kill Switch Interval**: Very short check intervals (< 10 seconds) can cause unnecessary resource usage. 30 seconds is recommended for most use cases.
>>>>>>> 304d5e53e4ab17992bd94ad1fff7465ee1d8920a

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LOCATIONS -->
## 🌍 Available Locations

Choose any **City**, **Country**, or **ISO Code** for `ADGUARD_CONNECTION_LOCATION`:

<details>
<summary><strong>🗺️ Complete Location List (Click to expand)</strong></summary>

| ISO | Country | City |
|:----|:--------|:-----|
| 🇺🇸 US | United States | Seattle, Silicon Valley, Phoenix, Las Vegas, Denver, Dallas, Los Angeles, Atlanta, New York, Miami, Boston, Chicago |
| 🇩🇪 DE | Germany | Berlin, Frankfurt |
| 🇬🇧 GB | United Kingdom | Manchester, London |
| 🇫🇷 FR | France | Paris, Marseille |
| 🇪🇸 ES | Spain | Barcelona, Madrid |
| 🇮🇹 IT | Italy | Rome, Milan, Palermo |
| 🇨🇦 CA | Canada | Vancouver, Montreal, Toronto |
| 🇯🇵 JP | Japan | Tokyo |
| 🇰🇷 KR | South Korea | Seoul |
| 🇦🇺 AU | Australia | Sydney |
| 🇸🇬 SG | Singapore | Singapore |
| 🇭🇰 HK | Hong Kong | Hong Kong |
| 🇹🇼 TW | Taiwan | Taipei |
| 🇳🇱 NL | Netherlands | Amsterdam |
| 🇨🇭 CH | Switzerland | Zurich |
| 🇦🇹 AT | Austria | Vienna |
| 🇧🇪 BE | Belgium | Brussels |
| 🇩🇰 DK | Denmark | Copenhagen |
| 🇫🇮 FI | Finland | Helsinki |
| 🇳🇴 NO | Norway | Oslo |
| 🇸🇪 SE | Sweden | Stockholm |
| 🇵🇱 PL | Poland | Warsaw |
| 🇨🇿 CZ | Czechia | Prague |
| 🇭🇺 HU | Hungary | Budapest |
| 🇷🇴 RO | Romania | Bucharest |
| 🇧🇬 BG | Bulgaria | Sofia |
| 🇬🇷 GR | Greece | Athens |
| 🇪🇪 EE | Estonia | Tallinn |
| 🇱🇻 LV | Latvia | Riga |
| 🇱🇹 LT | Lithuania | Vilnius |
| 🇱🇺 LU | Luxembourg | Luxembourg |
| 🇮🇪 IE | Ireland | Dublin |
| 🇵🇹 PT | Portugal | Lisbon |
| 🇷🇺 RU | Russia | Moscow |
| 🇺🇦 UA | Ukraine | Kyiv |
| 🇰🇿 KZ | Kazakhstan | Astana |
| 🇲🇩 MD | Moldova | Chișinău |
| 🇷🇸 RS | Serbia | Belgrade |
| 🇭🇷 HR | Croatia | Zagreb |
| 🇸🇰 SK | Slovakia | Bratislava |
| 🇨🇾 CY | Cyprus | Nicosia |
| 🇮🇸 IS | Iceland | Reykjavik |
| 🇹🇷 TR | Turkey | Istanbul |
| 🇮🇱 IL | Israel | Tel Aviv |
| 🇦🇪 AE | UAE | Dubai |
| 🇪🇬 EG | Egypt | Cairo |
| 🇮🇷 IR | Iran | Tehran |
| 🇮🇳 IN | India | Mumbai |
| 🇨🇳 CN | China | Shanghai |
| 🇹🇭 TH | Thailand | Bangkok |
| 🇻🇳 VN | Vietnam | Hanoi |
| 🇵🇭 PH | Philippines | Manila |
| 🇮🇩 ID | Indonesia | Jakarta |
| 🇰🇭 KH | Cambodia | Phnom Penh |
| 🇳🇵 NP | Nepal | Kathmandu |
| 🇳🇿 NZ | New Zealand | Auckland |
| 🇿🇦 ZA | South Africa | Johannesburg |
| 🇳🇬 NG | Nigeria | Lagos |
| 🇧🇷 BR | Brazil | São Paulo |
| 🇦🇷 AR | Argentina | Buenos Aires |
| 🇨🇱 CL | Chile | Santiago |
| 🇨🇴 CO | Colombia | Bogotá |
| 🇵🇪 PE | Peru | Lima |
| 🇲🇽 MX | Mexico | Mexico City |

</details>

### 🎯 Quick Examples
```bash
ADGUARD_CONNECTION_LOCATION="US"              # Any US server
ADGUARD_CONNECTION_LOCATION="Japan"           # Any Japan server
ADGUARD_CONNECTION_LOCATION="London"          # London specifically
ADGUARD_CONNECTION_LOCATION="Silicon Valley" # Silicon Valley specifically
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- ARCHITECTURE SUPPORT -->
## 🏗️ Multi-Architecture Support

This project provides **native performance** across all major architectures:

### 🖥️ Supported Platforms

| Architecture | Platform Examples | Performance |
|--------------|-------------------|-------------|
| **amd64** | Intel/AMD desktops, cloud instances | ⚡ Excellent |
| **arm64** | Apple Silicon (M1/M2/M3), ARM servers | ⚡ Native |
| **armv7** | Raspberry Pi 3/4, IoT devices | ✅ Optimized |

### 🚀 Architecture Detection

Docker automatically selects the optimal image for your platform:

```bash
# Same command works everywhere
docker pull supersunho/adguardvpn-cli:latest

# Results:
# Intel/AMD (x86_64)    → pulls amd64 image
# Apple Silicon (M1/M2) → pulls arm64 image
# Raspberry Pi          → pulls armv7 image
```

### 🔧 Manual Architecture Selection

If needed, you can explicitly specify an architecture:

```bash
# Intel/AMD optimized
docker pull supersunho/adguardvpn-cli:latest-amd64

# Apple Silicon optimized
docker pull supersunho/adguardvpn-cli:latest-arm64

# Raspberry Pi optimized
docker pull supersunho/adguardvpn-cli:latest-armv7
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- BUILD INFORMATION -->
## 🤖 Automated Builds

### 📅 Build Schedule
- **Daily Builds**: Automatically track latest AdGuard VPN CLI releases
- **Manual Triggers**: On-demand builds via GitHub Actions
- **Multi-Registry**: Simultaneous publishing to Docker Hub and GHCR

### 🔍 Build Verification
Every build includes comprehensive testing:
- ✅ Binary verification across all architectures
- ✅ Version compatibility checks  
- ✅ Container health validation
- ✅ Multi-platform manifest creation

### 📊 Build Status
Check the latest build status: [GitHub Actions](https://github.com/supersunho/docker-adguardvpn-cli/actions)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- TROUBLESHOOTING -->
## 🔧 Troubleshooting

### Common Issues

<details>
<summary><strong>VPN connection fails</strong></summary>

1. **Check credentials**: Ensure `ADGUARD_USERNAME` and `ADGUARD_PASSWORD` are correct
2. **Verify location**: Use a valid location from the [Available Locations](#-available-locations) list
3. **Check permissions**: Container needs `NET_ADMIN` capability and `/dev/net/tun` access

```bash
docker logs adguard-vpn-cli
```
</details>

<details>
<summary><strong>Kill switch not working</strong></summary>

1. **Enable kill switch**: Set `ADGUARD_USE_KILL_SWITCH=true`
2. **Check interval**: Ensure `ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL` is reasonable (≥10 seconds)
3. **Network configuration**: Verify TUN interface is available

</details>

<details>
<summary><strong>SOCKS5 proxy not accessible</strong></summary>

1. **Host binding**: Set `ADGUARD_SOCKS5_HOST=0.0.0.0` for external access
2. **Authentication**: Configure `ADGUARD_SOCKS5_USERNAME` and `ADGUARD_SOCKS5_PASSWORD`
3. **Port mapping**: Ensure Docker port mapping matches `ADGUARD_SOCKS5_PORT`

</details>

### 🩺 Health Checking

```bash
# Check container health
docker inspect adguard-vpn-cli --format='{{.State.Health.Status}}'

# View detailed logs
docker logs --follow adguard-vpn-cli

# Test VPN connectivity
docker exec adguard-vpn-cli curl -s ipinfo.io/ip
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRIBUTING -->
## 🤝 Contributing

Contributions make the open source community amazing! Any contributions are **greatly appreciated**.

### Development Setup

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### 🐛 Reporting Issues

Found a bug? Please check existing [issues](https://github.com/supersunho/docker-adguardvpn-cli/issues) first, then create a new one with:

- **Environment details** (OS, Docker version, architecture)
- **Steps to reproduce**
- **Expected vs actual behavior**
- **Relevant logs**

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- ACKNOWLEDGMENTS -->
## 🙏 Acknowledgments

- [AdGuard Team](https://github.com/AdguardTeam/AdGuardVPNCLI) - Original AdGuard VPN CLI 

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LINKS AND IMAGES -->
[contributors-shield]: https://img.shields.io/github/contributors/supersunho/docker-adguardvpn-cli.svg?style=for-the-badge
[contributors-url]: https://github.com/supersunho/docker-adguardvpn-cli/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/supersunho/docker-adguardvpn-cli.svg?style=for-the-badge
[forks-url]: https://github.com/supersunho/docker-adguardvpn-cli/network/members
[stars-shield]: https://img.shields.io/github/stars/supersunho/docker-adguardvpn-cli.svg?style=for-the-badge
[stars-url]: https://github.com/supersunho/docker-adguardvpn-cli/stargazers
[issues-shield]: https://img.shields.io/github/issues/supersunho/docker-adguardvpn-cli.svg?style=for-the-badge
[issues-url]: https://github.com/supersunho/docker-adguardvpn-cli/issues
[dockerhub-shield]: https://img.shields.io/docker/pulls/supersunho/adguardvpn-cli?style=for-the-badge&logo=docker
[dockerhub-url]: https://hub.docker.com/r/supersunho/adguardvpn-cli
[ghcr-shield]: https://img.shields.io/badge/ghcr.io-supersunho%2Fdocker--adguardvpn--cli-blue?style=for-the-badge&logo=github
[ghcr-url]: https://github.com/supersunho/docker-adguardvpn-cli/pkgs/container/docker-adguardvpn-cli

 
