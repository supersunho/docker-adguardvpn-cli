<!-- Improved compatibility of back to top link: See: https://github.com/othneildrew/Best-README-Template/pull/73 -->

<a id="readme-top"></a>

<!--
*** Thanks for checking out the Best-README-Template. If you have a suggestion
*** that would make this better, please fork the repo and create a pull request
*** or simply open an issue with the tag "enhancement".
*** Don't forget to give the project a star!
*** Thanks again! Now go create something AMAZING! :D
-->

<!-- PROJECT SHIELDS -->
<!--
*** I'm using markdown "reference style" links for readability.
*** Reference links are enclosed in brackets [ ] instead of parentheses ( ).
*** See the bottom of this document for the declaration of the reference variables
*** for contributors-url, forks-url, etc. This is an optional, concise syntax you may use.
*** https://www.markdownguide.org/basic-syntax/#reference-style-links
-->

[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]

<div align="center">
  <!-- <a href="https://github.com/supersunho/docker-adguardvpn-cli">
    <img src="images/logo.png" alt="Logo" width="80" height="80">
  </a> -->

<h3 align="center">Docker-AdguardVPN-CLI</h3>

  <p align="center">
    <a href="https://github.com/AdguardTeam/AdGuardVPNCLI">AdGuard VPN CLI</a> within a Docker container
    <!-- <br />
    <a href="https://github.com/github_username/repo_name"><strong>Explore the docs »</strong></a>
    <br /> -->
    <br />
    <!-- <a href="https://github.com/github_username/repo_name">View Demo</a>
    &middot; -->
    <a href="https://github.com/supersunho/docker-adguardvpn-cli/issues/new?labels=bug&template=bug-report---.md">Report Bug</a>
    &middot;
    <a href="https://github.com/supersunho/docker-adguardvpn-cli/issues/new?labels=enhancement&template=feature-request---.md">Request Feature</a>
  </p>
</div>

<!-- ABOUT THE PROJECT -->

## About The Project

<!-- [![Product Name Screen Shot][product-screenshot]](https://example.com) -->

This project allows you to use AdguardVPN-CLI within a Docker container. It provides a simple and efficient way to manage AdguardVPN through the command line in a containerized environment.

> [!IMPORTANT]
> **Authentication Change Notice**: As of version 1.5.10, AdGuard VPN CLI has transitioned from username/password authentication to web-based authentication. The old `ADGUARD_USERNAME` and `ADGUARD_PASSWORD` environment variables are no longer used for authentication, but are kept for backward compatibility in configuration.

<!--

### Built With

* [![Next][Next.js]][Next-url]
* [![React][React.js]][React-url]
* [![Vue][Vue.js]][Vue-url]
* [![Angular][Angular.io]][Angular-url]
* [![Svelte][Svelte.dev]][Svelte-url]
* [![Laravel][Laravel.com]][Laravel-url]
* [![Bootstrap][Bootstrap.com]][Bootstrap-url]
* [![JQuery][JQuery.com]][JQuery-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p> -->

<!-- GETTING STARTED -->

## Getting Started

Before proceeding, please review the following content and create your .env file accordingly. You can refer to the .env.example file provided in this repository for guidance.

### Data Directory Ownership

The container runs as a non-root user with UID/GID `1001:1001`. Before first run, ensure the local `data` directory has the correct ownership:

```bash
mkdir -p data
sudo chown -R 1001:1001 data
cp .env.example .env
docker compose up -d
```

> [!IMPORTANT]
> The published Docker image uses a fixed UID/GID of `1001:1001` for the `appuser`. Changing `PUID` and `PGID` in `.env` does **not** remap the runtime user. These are build-time arguments only — use them only when building a custom image. If the `data` directory is not writable, the container will exit immediately with a `chown` hint.

### Authentication Setup

> [!IMPORTANT]
> **New Authentication Process**: AdGuard VPN CLI now uses web-based authentication (OAuth device code flow). You need to perform an initial authentication via browser before the VPN can connect.

1. **First-time Setup**:
    - Start the main container: `docker-compose up -d`
    - Check the logs to find the authentication link: `docker logs adguard-vpn-cli`
    - The log will display a message like:
      ```
      You need to authorize in your browser. The following link will be available for 1799 seconds:
      https://auth.adguard.io/device_code?user_code=XXXX-XXXX
      ```
    - Open the link in your browser and complete authentication
    - Wait a moment for the process to continue automatically
    - **Note**: If Two-Factor Authentication (2FA) is enabled on your account, you may experience issues with this login process.

2. **Volume Mount**: The container mounts `./data` directory to persist authentication credentials across container restarts. The data directory is located at `/home/appuser/.local/share/adguardvpn-cli/` inside the container.

<!-- USAGE EXAMPLES -->

## How to use

AdguardVPN-CLI + qBittorrent

```yml
version: "3"
services:
    adguard-vpn-cli:
        image: supersunho/adguardvpn-cli:latest
        restart: unless-stopped
        container_name: adguard-vpn-cli
        env_file: .env
        volumes:
            - ./data:/home/appuser/.local/share/adguardvpn-cli
        healthcheck:
            test: ["CMD-SHELL", "adguardvpn-cli status >/dev/null 2>&1 || exit 1"]
            interval: 1m
            timeout: 10s
            retries: 2
            start_period: 30s
        cap_add:
            - NET_ADMIN
        devices:
            - /dev/net/tun
        ports:
            - 6089:6089
            - 6881:6881
            - 6881:6881/udp
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

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Prerequisites

| Variable                               | Description                                                                                                                                      | Default value | Allowed values              |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------- | --------------------------- |
| ADGUARD_CONNECTION_LOCATION            | VPN server location code                                                                                                                         | JP            | e.g. JP, US, SG, NL         |
| ADGUARD_CONNECTION_TYPE                | VPN operating mode                                                                                                                               | TUN           | TUN / SOCKS                 |
| ADGUARD_SOCKS5_USERNAME                | SOCKS5 proxy username                                                                                                                            | username      |                             |
| ADGUARD_SOCKS5_PASSWORD                | SOCKS5 proxy password                                                                                                                            | password      |                             |
| ADGUARD_SOCKS5_HOST                    | SOCKS5 proxy host address                                                                                                                        | 127.0.0.1     | IPv4 address                |
| ADGUARD_SOCKS5_PORT                    | SOCKS5 proxy port                                                                                                                                | 1080          | Port 1-65535                |
| ADGUARD_USE_KILL_SWITCH                | Enable kill switch to prevent IP leaks when VPN drops                                                                                           | true          | true / false                |
| ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL | Kill switch check interval in seconds                                                                                                            | 15            | Positive integer            |
| ADGUARD_MAX_LEAK_TOLERANCE             | Number of leak detections before termination (0 = immediate)                                                                                     | 0             | Positive integer            |
| ADGUARD_LEAK_WARNING_ONLY              | Only warn on leaks, do not terminate                                                                                                             | false         | true / false                |
| ADGUARD_MAX_IP_DETECTION_RETRIES       | Maximum IP detection retry attempts                                                                                                              | 3             | Positive integer            |
| ADGUARD_IP_DETECTION_RETRY_DELAY       | Delay in seconds between IP detection retries                                                                                                    | 10            | Positive integer            |
| ADGUARD_USE_CUSTOM_DNS                 | Use a custom DNS server instead of the system default                                                                                            | true          | true / false                |
| ADGUARD_CUSTOM_DNS                     | Custom DNS server address                                                                                                                        | 1.1.1.1       | IPv4 or hostname            |
| ADGUARD_SET_SYSTEM_DNS                 | Allow AdGuard VPN to change the system DNS configuration                                                                                         | false         | true / false                |
| ADGUARD_SEND_REPORTS                   | Send crash reports to AdGuard                                                                                                                    | false         | true / false                |
| ADGUARD_TELEMETRY                      | Send anonymous telemetry data                                                                                                                    | false         | true / false                |
| ADGUARD_AUTO_UPDATE                    | Automatically update AdGuard VPN CLI on startup                                                                                                  | false         | true / false                |
| ADGUARD_UPDATE_CHANNEL                 | Update channel                                                                                                                                   | release       | release / beta / dev        |
| ADGUARD_SHOW_HINTS                     | Show CLI usage hints                                                                                                                             | on            | on / off                    |
| ADGUARD_SHOW_NOTIFICATIONS             | Show desktop notifications                                                                                                                       | on            | on / off                    |
| ADGUARD_PROTOCOL                       | VPN protocol                                                                                                                                     | auto          | auto / TCP / QUIC           |
| ADGUARD_POST_QUANTUM                   | Post-quantum encryption                                                                                                                          | off           | on / off                    |
| ADGUARD_TUN_ROUTING_MODE               | TUN routing mode                                                                                                                                 | AUTO          | AUTO / TUN_ONLY / PROXY_ONLY|
| ADGUARD_BOUND_IF_OVERRIDE              | Override bound network interface (empty = auto)                                                                                                  |               | Interface name or empty     |
| ADGUARD_SHOW_LOG                       | Master switch for container log output (false = silent, except critical messages like OAuth URL)                                                 | true          | true / false                |
| ADGUARD_SHOW_LOG_LEVEL                 | Container log level filter                                                                                                                       | INFO          | DEBUG / INFO / WARN / ERROR |
| ADGUARD_SHOW_SUMMARY                   | Show kill switch periodic summary in container logs                                                                                              | true          | true / false                |
| ADGUARD_MAX_WAIT_TIME                  | Maximum wait time in seconds for the AdGuard VPN log file to appear                                                                              | 60            | Positive integer            |
| PUID                                   | **[Build-time only]** User ID for the container's app user (default avoids conflict with Ubuntu 24.04 built-in ubuntu user at 1000)              | 1001          | Positive integer (build arg)|
| PGID                                   | **[Build-time only]** Group ID for the container's app user (default avoids conflict with Ubuntu 24.04 built-in ubuntu group at 1000)            | 1001          | Positive integer (build arg)|

> [!IMPORTANT]
>
> - `ADGUARD_SOCKS5_HOST`: For non-localhost addresses, you need to protect the proxy with a username and password.
> - `ADGUARD_USE_CUSTOM_DNS`: Set to `true` to use the DNS server specified by `ADGUARD_CUSTOM_DNS`, or `false` to skip custom DNS configuration.
> - `ADGUARD_CUSTOM_DNS`: Set the DNS upstream server value, for example `1.1.1.1`, `8.8.8.8`, or another DNS server supported by AdGuard VPN CLI.
> - `ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL`: A very short check interval is not recommended.
> - **Authentication Variables**: `ADGUARD_USERNAME` and `ADGUARD_PASSWORD` are no longer used for authentication as of version 1.5.10. Authentication is now done via web-based flow. These variables are kept for backward compatibility in other configuration aspects.

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
<!-- ACKNOWLEDGMENTS -->

## References

- [AdguardTeam/AdGuardVPNCLI](https://github.com/AdguardTeam/AdGuardVPNCLI)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->

[contributors-shield]: https://img.shields.io/github/contributors/supersunho/docker-adguardvpn-cli.svg?style=for-the-badge
[contributors-url]: https://github.com/supersunho/docker-adguardvpn-cli/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/supersunho/docker-adguardvpn-cli.svg?style=for-the-badge
[forks-url]: https://github.com/supersunho/docker-adguardvpn-cli/network/members
[stars-shield]: https://img.shields.io/github/stars/supersunho/docker-adguardvpn-cli.svg?style=for-the-badge
[stars-url]: https://github.com/supersunho/docker-adguardvpn-cli/stargazers
[issues-shield]: https://img.shields.io/github/issues/supersunho/docker-adguardvpn-cli.svg?style=for-the-badge
[issues-url]: https://github.com/supersunho/docker-adguardvpn-cli/issues
[license-shield]: https://img.shields.io/github/license/supersunho/docker-adguardvpn-cli.svg?style=for-the-badge
[license-url]: https://github.com/supersunho/docker-adguardvpn-cli/blob/master/LICENSE.txt
[linkedin-shield]: https://img.shields.io/badge/-LinkedIn-black.svg?style=for-the-badge&logo=linkedin&colorB=555
[linkedin-url]: https://linkedin.com/in/supersunho
[product-screenshot]: images/screenshot.png
