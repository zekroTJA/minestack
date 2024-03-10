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
    read

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
    domains=("$@")

    set -- $(hostname -I)
    myip="$1"

    erroneous=()
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

    if [ -n "$erroneous" ]; then
        echo -e "\n${F_BOLD}${C_ORANGE}warning:${F_RESET} some domains don't bind to this servers IP address ${F_ITALIC}${C_CYAN}($myip)${F_RESET}:"
        for err in "${erroneous[@]}"; do
            echo -e "  - $err"
        done

        echo -e "\nDo you want to continue anyway? ${F_ITALIC}(y/N)${F_RESET}"
        echo -e "⚠️  Continuing with unset domain values can result in issues when issuing the TLS certificates for the public websites on startup."
        read yn
        case "$yn" in
            "y"|"Y"|"yes") ;;
            *) exit 1 ;;
        esac
    else
        echo -e "\n${C_GREEN}All domains DNS entries are correctly configured!${F_RESET}"
    fi
}

error() {
    echo -e "${C_RED}${F_BOLD}error:${F_RESET} $1"
}

# -------------------------------------------------------------------------

missing=()
which curl > /dev/null 2>&1 || missing+=("docker")
which curl > /dev/null 2>&1 || missing+=("curl")
which jq > /dev/null 2>&1 || missing+=("jq")
if [ -n "$missing" ]; then
    error "The following tools are missing on your system:"
    for t in ${missing[*]}; do
        echo -e "  - $t"
    done
    echo -e ""
    echo -e "Please install them and re-start the script."
    exit 1
fi

set -e

echo -e "${F_BOLD}${C_CYAN}Heyo! 👋 This script will lead you though the necessary steps to set up your Minecraft server!${F_RESET} 🚀"

echo -e "\n${C_GREY}(1)${F_RESET} Please enter the ${F_BOLD}${C_PINK}domain${F_RESET} of your server ${F_ITALIC}(i.e. 'mc.example.com')${F_RESET}:"
read domain

if [ -z "$domain" ]; then
    error "Value for domain can not be empty!"
    exit 1
fi

check_domain_binding "$domain" "docker.$domain" "grafana.$domain"

echo -e "ROOT_DOMAIN=$domain" > ".env"

echo -e "\n${C_GREY}(2)${F_RESET} Do you want to enable ${F_BOLT}${C_PINK}automatic backups${F_RESET}? ${F_ITALIC}(Y/n)${F_RESET}"
read yn
case "$yn" in
    "n"|"N"|"no") echo -e "Automatic backups are not enabled." ;;
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

echo -e "\n${C_GREY}(3)${F_RESET} Do you want to start the stack now ${F_RESET} ${F_ITALIC}(Y/n)${F_RESET}?"
read yn
case "$yn" in
    "n"|"N"|"no")
        echo -e "${C_GREEN}Setup finished!${F_RESET}"
        echo -e "You can start the stack at any time with ${F_ITALIC}'docker compose up -d'${F_RESET}! ;)"
        ;;
    *)
        docker compose up -d
        echo -e "${C_GREEN}Stack has been started!${F_RESET}"
        echo -e ""
        echo -e "Next steps:"
        echo -e "  - Check stack status with ${F_ITALIC}'docker compose ps'${F_RESET} and ${F_ITALIC}'docker compose logs'${F_RESET}."
        echo -e "  - Go to ${F_UNERLINE}${C_CYAN}https://docker.$domain${F_RESET} to configure Portainer."
        echo -e "  - Go to ${F_UNERLINE}${C_CYAN}https://$domain${F_RESET} to check your BlueMap (when the server has finished building)."
        echo -e "  - Connect to your server via ${C_CYAN}$domain${F_RESET}."
        echo -e "  - Have fun! :)"
        ;;
esac
