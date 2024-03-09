# minestack

minestack is a very simple [Docker Compose](https://docs.docker.com/compose/) stack to quickly spin up a [spigot](https://www.spigotmc.org/) Minecraft server with [BlueMap](https://bluemap.bluecolored.de/), [Portainer](https://www.portainer.io/) and [Grafana](https://grafana.com/).

## Prerequisite

- You need a server which is capable of running a Minecraft server. This could be a home server, a VPS or - in the best case - a root server.
- You need a domain to bind the server to. This can also be a dyndns domain if you don't want to pay for a domain.
- You need the following tools installed on your server.
  - `git` _(should be installed by default on most distros)_
  - `ssh` _(should be installed by default on most distros)_
  - `docker`
  - `curl`
  - `jq`

## Setup

1. Clone this repository to your server.

   ```
   git clone https://github.com/zekroTJA/minestack.git --branch main --depth 1
   ```

2. Execute the `init.sh` script.
   ```
   ./init.sh
   ```

And you should be ready to go!
