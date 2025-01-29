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

<p align="right">(<a href="#readme-top">back to top</a>)</p>

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

### Prerequisites

| Variable                    | Description                        | Default value | Allow values |
| --------------------------- | ---------------------------------- | ------------- | ------------ |
| ADGUARD_USERNAME            | Username for login                 | "username"    |              |
| ADGUARD_PASSWORD            | Password for login                 | "password"    |              |
| ADGUARD_CONNECTION_LOCATION | Defaults to the last used location | "JP"          |
| ADGUARD_CONNECTION_TYPE     | Set VPN operating mode             | "TUN"         | TUN / SOCKS5 |
| ADGUARD_SOCKS5_USERNAME     | Set the SOCKS username             | "username"    |              |
| ADGUARD_SOCKS5_PASSWORD     | Set the SOCKS password             | "password"    |              |
| ADGUARD_SOCKS5_HOST         | Set the SOCKS listen host.         | "127.0.0.1"   |              |
| ADGUARD_SOCKS5_PORT         | Set the SOCKS port                 | 1080          |              |
| ADGUARD_SEND_REPORTS        | Send crash reports to developers   | false         |              |
| ADGUARD_SET_SYSTEM_DNS      | Set the system DNS servers         | false         |              |
| ADGUARD_USE_CUSTOM_DNS      | Use the custom DNS servers         | true          |              |
| ADGUARD_CUSTOM_DNS          | Set the DNS upstream server        | "1.1.1.1"     |              |
| ADGUARD_USE_QUIC            | Set whether to use QUIC protocol   | true          |              |

> [!IMPORTANT]
> `ADGUARD_SOCKS5_HOST`: For non-localhost addresses, you need to protect the proxy with a username and password.

### Installation

```sh
docker compose up -d
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- USAGE EXAMPLES -->

## Usage

아래는 AdgaurdVPNCLI를 사용해서 qBittorrent를 사용한 docker-compose.yml입니다.
```yml
version: "3"
services:
    adguard-vpn-cli:
        image: ghcr.io/supersunho/docker-adguardvpn-cli:latest
        restart: unless-stopped
        container_name: adguard-vpn-cli
        env_file: .env
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
        labels:
            - "com.centurylinklabs.watchtower.enable=false"
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
