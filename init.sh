#!/bin/bash

C_RED="\033[38;5;203m"
C_CYAN="\033[38;5;87m"
C_PINK="\033[38;5;199m"
C_GREEN="\033[38;5;48m"
C_ORANGE="\033[38;5;214m"
C_GREY="\033[38;5;246m"
F_BOLD="\033[1m"
F_ITALIC="\033[3m"
F_UNDERLINE="\033[4m"
F_RESET="\033[0m"

# -------------------------------------------------------------------------

setup_rclone_config() {
    echo -e "Following, the rclone configuration wizzard will open where you can add a new remote configuration for your backup archives."
    echo -e ""
    echo -e "⚠️ In the wizzard, enter ${F_BOLD}${F_ITALIC}${C_PINK}'e'${F_RESET} to create a new config with the name ${F_BOLD}${F_ITALIC}${C_PINK}'minecraft'${F_RESET} (this is important!)"
    echo -e "After that, choose the storage type and continue the setup process."
    echo -e ""
    echo -e "If you need help, please refer to the rclone documentation:"
    echo -e "https://rclone.org/commands/rclone_config"
    echo -e ""
    echo -e "${F_ITALIC}Press ENTER to continue ...${F_RESET}"
    read -r

    if ! [ -d "rclone" ]; then
        mkdir rclone
    fi
    docker run \
        --rm -it -v "$PWD/rclone:/config/rclone" -u "$(id -u)" rclone/rclone:latest \
            config

    if ! grep '^\[minecraft\]$' rclone/rclone.conf > /dev/null 2>&1; then
        error "Could not find a config for ${F_BOLD}${C_PINK}'minecraft'${F_RESET} in the created rclone.conf."
        exit 1
    fi

    sed -i '1s#^#secrets:\n  minecraftrclone:\n    file: rclone/rclone.conf\n\n#' docker-compose.yml
    sed -i 's#PRE_START_BACKUP: "false"#PRE_START_BACKUP: "true"#' docker-compose.yml
    sed -i '#secrets: \[\]#secrets:\n      - source: minecraftrclone\n        target: rcloneconfig#' docker-compose.yml
}

check_domain_binding() {
    local domains=("$@")

    # shellcheck disable=SC2046
    set -- $(hostname -I)
    local myip="$1"

    local erroneous=()
    local resolved
    local domain
    for domain in "${domains[@]}"; do
        resolved=$(dig +short "$domain" | tail -n1)
        if [ "$resolved" != "$myip" ]; then
            if [ -z "$resolved" ]; then
                erroneous+=("$domain -> ${C_GREY}unset${F_RESET}")
            else
                erroneous+=("$domain -> ${C_RED}${resolved}${F_RESET}")
            fi
        fi
    done

    if [ -n "${erroneous[*]}" ]; then
        echo -e "\n${F_BOLD}${C_ORANGE}warning:${F_RESET} some domains don't bind to this servers IP address ${F_ITALIC}${C_CYAN}($myip)${F_RESET}:"
        local err
        for err in "${erroneous[@]}"; do
            echo -e "  - $err"
        done

        echo -e "\nDo you want to continue anyway? ${F_ITALIC}(y/N)${F_RESET}"
        echo -e "⚠️  Continuing with unset domain values can result in issues when issuing the TLS certificates for the public websites on startup."
        read -r yn
        case "$yn" in
            "y"|"Y"|"yes") ;;
            *) exit 1 ;;
        esac
    else
        echo -e "\n${C_GREEN}All domains DNS entries are correctly configured!${F_RESET}"
    fi
}

check_srv() {
    local domain="$1"
    # shellcheck disable=SC2046
    set -- $(dig SRV +short "_minecraft._tcp.$domain" | cut -d ' ' -f 3,4)
    if [ -z "$1" ]; then
        echo -e "\n⚠️  No SRV entry for '_minecraft._tcp.$domain' has been detected. Defaulting to default Minecraft port (${F_ITALIC}25565${F_RESET})."
        minecraft_port="25565"
    else
        minecraft_port="$1"
        echo -e "\n${C_GREEN}Detected port ${C_CYAN}${F_ITALIC}${minecraft_port}${F_RESET}${C_GREEN} from SRV entry.${F_RESET}"
    fi
}

insert_backup_cronjob() {
    if ! [ -d "/etc/cron.d" ]; then
        error "path /etc/cron.d does not exist? Is cron properly installed on your system?"
        exit 1
    fi

    output_dir="/etc/cron.d/minecraft-server"

    echo "⚠️  Creating the crontab entry for the root user requires sudo permissions!"
    container_name="${PWD##*/}-spigot"
    {
        echo " 0 7 * * * docker exec $container_name rcon 'say ATTENTION: Server will restart in one hour!'"
        echo "30 7 * * * docker exec $container_name rcon 'say ATTENTION: Server will restart in 30 minutes!'"
        echo "50 7 * * * docker exec $container_name rcon 'say ATTENTION: Server will restart in 10 minutes!'"
        echo "55 7 * * * docker exec $container_name rcon 'say ATTENTION: Server will restart in 5 minutes!'"
        echo "59 7 * * * docker exec $container_name rcon 'say ATTENTION: Server will restart in one minutes!'"
        echo " 0 8 * * * docker exec $container_name rcon 'stop'"
    } | sudo tee "$output_dir"

    echo -e "\n${C_GREEN}Restart crontab entry has been created (${F_ITALIC}${output_dir}${F_RESET}${C_GREEN}).${F_RESET}"
}

select_minecraft_version() {
    local latest_version
    latest_version=$(curl -Ls https://launchermeta.mojang.com/mc/game/version_manifest.json | jq -r '.latest.release')

    local selected_version
    if which fzf > /dev/null 2>&1; then
        selected_version=$(curl -Ls https://launchermeta.mojang.com/mc/game/version_manifest.json \
            | jq -r '.versions[] | select(.type == "release") | .id' \
            | fzf --border rounded --header "Please select a Minecraft version for your server:" --info hidden)
    else
        echo -e "\nPlease enter the version of Minecraft you want to use ${F_ITALIC}(press enter to use latest ($latest_version))${F_RESET}:"
        read -r selected_version
    fi

    if [ -z "$selected_version" ]; then
        selected_version=$latest_version
    fi

    if [ "$(curl -so /dev/null -w "%{response_code}" "https://hub.spigotmc.org/versions/$selected_version.json")" == "200" ]; then
        echo -e "\n✅ ${C_GREEN}Spigot build for selected version exists!${F_RESET}"
    else
        error "No spigot build exists for the selected Minecraft version. Maybe you want to select an older version."
        exit 1
    fi

    minecraft_version=$selected_version
}

error() {
    echo -e "${C_RED}${F_BOLD}error:${F_RESET} $1"
}

# -------------------------------------------------------------------------

missing=()
which docker > /dev/null 2>&1 || missing+=("docker")
which curl > /dev/null 2>&1 || missing+=("curl")
which jq > /dev/null 2>&1 || missing+=("jq")
which dig > /dev/null 2>&1 || missing+=("dig")
which sudo > /dev/null 2>&1 || missing+=("sudo")
if [ -n "${missing[*]}" ]; then
    error "The following tools are missing on your system:"
    for t in "${missing[@]}"; do
        echo -e "  - $t"
    done
    echo -e ""
    echo -e "Please install them and re-start the script."
    exit 1
fi

set -e

echo -e "${F_BOLD}${C_CYAN}Heyo! 👋 This script will lead you though the necessary steps to set up your Minecraft server!${F_RESET} 🚀"

echo -e "\nPlease enter the ${F_BOLD}${C_PINK}domain${F_RESET} of your server ${F_ITALIC}(i.e. 'mc.example.com')${F_RESET}:"
read -r domain

if [ -z "$domain" ]; then
    error "Value for domain can not be empty!"
    exit 1
fi

check_domain_binding "$domain" "docker.$domain" "grafana.$domain"
check_srv "mc.$domain"

select_minecraft_version

{   echo -e "ROOT_DOMAIN=$domain"
    echo -e "MINECRAFT_VERSION=$minecraft_version"
    echo -e "MINECRAFT_PORT=$minecraft_port"
} > ".env"

echo -e "\nDo you want to enable ${F_BOLD}${C_PINK}automatic backups${F_RESET}? ${F_ITALIC}(Y/n)${F_RESET}"
read -r yn
case "$yn" in
    "n"|"N"|"no") echo -e "Automatic backups are not enabled." ;;
    *) setup_rclone_config ;;
esac

echo -e "\n Downloading required plugins:"
echo -e "  - Downloading latest version of BlueMap from GitHub ..."
# shellcheck disable=SC2046
set -- $(curl -Ls https://api.github.com/repos/BlueMap-Minecraft/BlueMap/releases \
    | jq -r '[ .[] | select ( .prerelease == false ) ][0].assets[] | select ( .name | endswith ("-spigot.jar" ) ) | .browser_download_url + " " + .name')
curl -Lso "spigot/plugins/$2" "$1"

echo -e "  - Downloading latest version of minecraft-prometheus-exporter from GitHub ..."
# shellcheck disable=SC2046
set -- $(curl -Ls https://api.github.com/repos/sladkoff/minecraft-prometheus-exporter/releases \
    | jq -r '[ .[] | select ( .prerelease == false ) ][0].assets[] | select ( .name | endswith (".jar") ) | .browser_download_url + " " + .name')
curl -Lso "spigot/plugins/$2" "$1"

echo -e "\nDo you want to enable ${F_BOLD}${C_PINK}automatic restarts${F_RESET}? ${F_ITALIC}(Y/n)${F_RESET}"
echo -e "⚠️  This is required to perform automatic backups, because backups can only be created on server startup."
read -r yn
case "$yn" in
    "n"|"N"|"no") echo -e "Automatic backups are not enabled." ;;
    *) insert_backup_cronjob ;;
esac

echo -e "\nDo you want to start the stack now? ${F_ITALIC}(Y/n)${F_RESET}"
read -r yn
case "$yn" in
    "n"|"N"|"no")
        echo -e "\n${C_GREEN}Setup finished!${F_RESET}"
        echo -e "You can start the stack at any time with ${F_ITALIC}'docker compose up -d'${F_RESET}! ;)"
        ;;
    *)
        docker compose up -d
        echo -e "\n${C_GREEN}Stack has been started!${F_RESET}"
        echo -e ""
        echo -e "Next steps:"
        echo -e "  - Check stack status with ${F_ITALIC}'docker compose ps'${F_RESET} and ${F_ITALIC}'docker compose logs'${F_RESET}."
        echo -e "  - Go to ${F_UNDERLINE}${C_CYAN}https://docker.$domain${F_RESET} to configure Portainer."
        echo -e "  - Go to ${F_UNDERLINE}${C_CYAN}https://$domain${F_RESET} to check your BlueMap (when the server has finished building)."
        echo -e "  - Connect to your server via ${C_CYAN}$domain${F_RESET}."
        echo -e "  - Have fun! :)"
        ;;
esac
