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

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]

<!-- PROJECT LOGO -->
<br />
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

Before proceeding, please review the following content and create your .env file accordingly. You can refer to the .env.sample file provided in this repository for guidance.

### Authentication Setup

> [!IMPORTANT]
> **New Authentication Process**: AdGuard VPN CLI now uses web-based authentication instead of username/password. You need to perform an initial authentication using the web flow before the VPN can connect.

1. **First-time Setup**:

    - Perform initial authentication: `./scripts/auth.sh` (or run directly: `docker run -it --rm -v $(pwd)/data:/root/.local/share/adguardvpn-cli --entrypoint "" supersunho/adguardvpn-cli:latest adguardvpn-cli login`)
    - Follow the instructions to authenticate in your browser
    - Start the main container: `docker-compose up -d`

2. **Volume Mount**: The container now mounts `./data` directory to persist authentication credentials across container restarts.

3. **Direct Command Execution**: If you need to run other AdGuard VPN CLI commands directly (not just login), you can use the `--entrypoint` option:
    - For login: `docker run -it --rm -v $(pwd)/data:/root/.local/share/adguardvpn-cli --entrypoint "" supersunho/adguardvpn-cli:latest adguardvpn-cli login`
    - For other commands: `docker run -it --rm -v $(pwd)/data:/root/.local/share/adguardvpn-cli --entrypoint "" supersunho/adguardvpn-cli:latest adguardvpn-cli [command]`

> [!NOTE]
> The default container entrypoint runs the VPN connection process automatically. To execute specific AdGuard VPN CLI commands directly, you need to override the entrypoint using the `--entrypoint` option as shown above.

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
            - ./data:/root/.local/share/adguardvpn-cli
        healthcheck:
            test: ping -c 1 www.google.com || exit 1
            interval: 1m
            timeout: 10s
            retries: 1
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

| Variable                               | Description                                                                                                                                      | Default value | Allow values             |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------- | ------------------------ |
| ADGUARD_USERNAME                       | Username for login                                                                                                                               | "username"    |                          |
| ADGUARD_PASSWORD                       | Password for login                                                                                                                               | "password"    |                          |
| ADGUARD_CONNECTION_LOCATION            | Defaults to the last used location                                                                                                               | "JP"          |                          |
| ADGUARD_CONNECTION_TYPE                | Set VPN operating mode                                                                                                                           | "TUN"         | TUN / SOCKS              |
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
| ADGUARD_TELEMETRY                      | Set whether to send anonymized usage data to developers                                                                                          | false         | true / false             |
| ADGUARD_TUN_ROUTING_MODE               | Set VPN tunnel routing mode                                                                                                                      | "AUTO"        | AUTO / SCRIPT / NONE     |
| ADGUARD_BOUND_IF_OVERRIDE              | Override network interface to use for outbound VPN traffic (pass "" to disable)                                                                  | ""            | interface name or ""     |
| ✨ADGUARD_MAX_LEAK_TOLERANCE           | Termination on first leak (0 = immediate termination on first leak)                                                                              | 0             |                          |
| ✨ADGUARD_LEAK_WARNING_ONLY            | When a leak, only an warning (true = warning only, false = terminate)                                                                            | false         | true / false             |
| ✨ADGUARD_MAX_IP_DETECTION_RETRIES     | Maximum number of IP detection attempts                                                                                                          | 3             | number                   |
| ✨ADGUARD_IP_DETECTION_RETRY_DELAY     | IP detection retry delay Seconds                                                                                                                 | 10            | number                   |

> [!IMPORTANT]
> `ADGUARD_SOCKS5_HOST`: For non-localhost addresses, you need to protect the proxy with a username and password.

> [!IMPORTANT]
> `ADGUARD_USE_KILL_SWITCH_CHECK_INTERVAL`: A very short check interval is not recommended.

> [!NOTE]
> **Authentication Variables**: `ADGUARD_USERNAME` and `ADGUARD_PASSWORD` are no longer used for authentication as of version 1.5.10. Authentication is now done via web-based flow. These variables are kept for backward compatibility in other configuration aspects.

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

-   [AdguardTeam/AdGuardVPNCLI](https://github.com/AdguardTeam/AdGuardVPNCLI)

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
