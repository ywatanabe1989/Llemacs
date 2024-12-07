#!/bin/bash
# Time-stamp: "2024-12-06 05:04:19 (ywatanabe)"
# File: ./self-evolving-agent/src/sea_server.sh

# Check if script is run with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (with sudo)"
    exit 1
fi

SEA_USER="${SEA_USER:-sea}"
SEA_HOME=/home/"${SEA_USER:-sea}"
SEA_UID=$(id -u "$SEA_USER")
SEA_SOCKET_DIR="$SEA_HOME"/.emacs.d/server
SEA_SOCKET_FILE="$SEA_SOCKET_DIR/server"

# Help message
show_help() {
    cat << EOF
SEA Server Control Script

Usage:
    $0 [command] [options]
    $0 execute "ELISP_CODE"    Execute elisp code in the server
                              Example: $0 execute '(message "hello")'

Commands:
    start       Start or connect to SEA server (default)
    kill        Kill the SEA server
    init     Init the SEA server
    status      Check server status
    execute     Execute elisp command
    help        Show this help message

Options:
    -u USER     SEA user (default: $SEA_USER)
    -s SOCKET   Socket name (default: $SEA_SOCKET_NAME)
    -h          Show this help message
EOF
    exit 0
}

# Argument parser
while getopts "u:s:h" opt; do
    case $opt in
        u) SEA_USER="$OPTARG" ;;
        s) SEA_SOCKET_NAME="$OPTARG" ;;
        h) show_help ;;
        ?) show_help ;;
    esac
done

shift $((OPTIND-1))
COMMAND="${1:-start}"

sea_kill_server() {
    if _sea_is_server_running; then
        sudo -u "$SEA_USER" emacsclient -e '(kill-emacs)' && sleep 1
        sudo rm "$SEA_SOCKET_FILE"
        if _sea_is_server_running; then
            sudo pkill -u "$SEA_USER" && sleep 1
        fi
    fi
}

sea_init_server() {
    sea_kill_server
    _sea_setup_server_dir

    # Start daemon
    sudo -u "$SEA_USER" \
         HOME="$SEA_HOME" \
         emacs \
         --daemon="$SEA_SOCKET_FILE" \
         --init-directory="$SEA_HOME/.emacs.d" &

    sudo -u "$SEA_USER" ls "$SEA_SOCKET_FILE"
    sudo -u "$SEA_USER" ls /home/sea/.emacs.d/server
}

sea_init_or_connect() {
    local connected=0
    if ! _sea_is_server_running; then
        sea_init_server
        sleep 1
    fi

    _sea_connect_server

}

sea_execute() {
    if _sea_is_server_running; then
        sudo -u "$SEA_USER" HOME="$SEA_HOME" emacsclient -s "$SEA_SOCKET_FILE" -e "$1"
    else
        echo "Server is not running"
        exit 1
    fi
}

_sea_is_server_running() {
    # Check process exists
    if ! pgrep -u "$SEA_USER" emacs >/dev/null; then
        return 1
    fi

    # Check server is accepting connections
    if ! sudo -u "$SEA_USER" HOME="$SEA_HOME" emacsclient -s "$SEA_SOCKET_FILE" -e '(version)' >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

_sea_setup_server_dir() {
    sudo rm -rf "$SEA_SOCKET_DIR"
    sudo -u "$SEA_USER" mkdir -p "$SEA_SOCKET_DIR"
    sudo chmod 700 "$SEA_SOCKET_DIR"
    sudo chown "$SEA_USER":"$SEA_USER" "$SEA_SOCKET_DIR"
    # sudo chmod 770 "$SEA_SOCKET_DIR"
    # sudo chmod 770 "$SEA_SOCKET_FILE"
    sudo chown "$SEA_USER":"$SEA_USER" "$SEA_SOCKET_DIR"
}

_sea_connect_server() {
    sudo -u "$SEA_USER" HOME="$SEA_HOME" emacsclient -s "$SEA_SOCKET_FILE" -c &
}


case "$COMMAND" in
    start)   sea_init_or_connect & ;;
    kill)    sea_kill_server & ;;
    init) sea_kill_server && sea_init_or_connect & ;;
    status)  _sea_is_server_running ;;
    execute) sea_execute "$2" & ;;
    help)    show_help ;;
    *)       show_help ;;
esac

# case "$COMMAND" in
#     start)   sea_init_or_connect & ;;
#     kill)    sea_kill_server & ;;
#     init) sea_kill_server && sea_init_or_connect & ;;
#     status)  _sea_is_server_running ;;
#     execute) sea_execute "$2" & ;;
#     help)    show_help ;;
#     *)       show_help ;;
# esac

# && echo "Server is running" || echo "Server is not running" ;;


# EOF