#!/bin/bash

setup_rclone_config() {
    echo "Following, the rclone configuration wizzard will open where you can add a new remote configuration for your backup archives."
    echo ""
    echo "In the wizzard, enter 'e' to create a new config with the name 'minecraft' (this is important!)"
    echo "After that, choose the storage type and continue the setup process."
    echo ""
    echo "If you need help, please refer to the rclone documentation:"
    echo "https://rclone.org/commands/rclone_config"
    echo ""
    echo "Press ENTER to continue ..."
    read

    mkdir rclone
    docker run \
        --rm -it -v "$PWD/rclone:/config/rclone" -u "$(id -u)" rclone/rclone:latest \
            config

    sed -i '1s#^#secrets:\n  minecraftrclone:\n    file: rclone/rclone.conf\n\n#' docker-compose.yml
    sed -i 's#PRE_START_BACKUP: "false"#PRE_START_BACKUP: "true"#' docker-compose.yml
    sed -i '#secrets: \[\]#secrets:\n      - source: minecraftrclone\n        target: rcloneconfig#' docker-compose.yml
}

# -------------------------------------------------------------------------

missing=()
which curl > /dev/null 2>&1 || missing+=("docker")
which curl > /dev/null 2>&1 || missing+=("curl")
which jq > /dev/null 2>&1 || missing+=("jq")
if [ -n "$missing" ]; then
    echo "error: The following tools are missing on your system:"
    for t in ${missing[*]}; do
        echo "  - $t"
    done
    echo ""
    echo "Please install them and re-start the script."
    exit 1
fi

set -e

echo "Heyo! This script will lead you though the necessary steps to set up your Minecraft server!"

echo -e "\n(1) Please enter the domain of your server (i.e. 'mc.example.com'):"
read domain

if [ -z "$domain" ]; then
    echo "error: Value for domain can not be empty!"
    exit 1
fi

echo "ROOT_DOMAIN=$domain" > ".env"

echo -e "\n(2) Do you want to enable automatic backups (Y/n)?"
read yn
case "$yn" in
    "n"|"N"|"no") echo "Automatic backups are not enabled." ;;
    *) setup_rclone_config ;;
esac

echo -e "\n Downloading required plugins:"
echo -e "  - Downloading latest version of BlueMap from GitHub ..."
set -- $(curl -Ls https://api.github.com/repos/BlueMap-Minecraft/BlueMap/releases \
    | jq -r '[ .[] | select ( .prerelease == false ) ][0].assets[] | select ( .name | endswith ("-spigot.jar" ) ) | .browser_download_url + " " + .name')
curl -Lso "spigot/plugins/$2" "$1"

echo -e "  - Downloading latest version of minecraft-prometheus-exporter from GitHub ..."
set -- $(curl -Ls https://api.github.com/repos/sladkoff/minecraft-prometheus-exporter/releases \
    | jq -r '[ .[] | select ( .prerelease == false ) ][0].assets[] | select ( .name | endswith (".jar") ) | .browser_download_url + " " + .name')
curl -Lso "spigot/plugins/$2" "$1"

echo -e "\n(3) Do you want to start the stack now (Y/n)?"
read yn
case "$yn" in
    "n"|"N"|"no")
        echo "Setup finished."
        echo "You can start the stack at any time with 'docker compose up -d'! ;)"
        ;;
    *)
        docker compose up -d
        echo "Stack has been started!"
        echo ""
        echo "Next steps:"
        echo "  - Check stack status with 'docker compose ps' and 'docker compose logs'."
        echo "  - Go to https://docker.$domain to configure Portainer."
        echo "  - Go to https://$domain to check your BlueMap (when the server has finished building)."
        echo "  - Connect to your server via $domain."
        echo "  - Have fun! :)"
        ;;
esac
