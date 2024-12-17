#!/bin/bash
# Time-stamp: "2024-12-18 04:35:54 (ywatanabe)"
# File: ./Ninja/.apptainer/ninja/ninja.sandbox/opt/Ninja/src/apptainer_builders/start_emacs_independently.sh

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    echo "This script ($0) must be run as root" >&2
    exit 1
fi

source "$(dirname $0)"/ENVS.sh.src

# Define shared_emacsd globally
shared_emacsd=/opt/Ninja/src/apptainer_builders/shared_emacsd

# Add at beginning of script
xhost +local:root > /dev/null 2>&1


init_environment() {
    killall -9 "$NINJA_EMACS_CLIENT" 2>/dev/null || true
    killall -9 "$NINJA_EMACS_BIN" 2>/dev/null || true

    # Global permissions
    chown -R root:$NINJAS_GROUP /home
    chown -R root:$NINJAS_GROUP $shared_emacsd
    chmod -R 750 $shared_emacsd
}

setup_user_directories() {
    local user=$1
    local user_socket_dir="/home/$user"

    # User directory setup
    mkdir -p $user_socket_dir
    chown -R $user:$NINJAS_GROUP $user_socket_dir
    chmod -R 750 $user_socket_dir

    # .emacs.d setup
    su - $user -c "rm -rf /home/$user/.emacs.d 2>&1 >/dev/null"
    su - $user -c "mkdir -p /home/$user/.emacs.d 2>&1 >/dev/null"
    chown $user:$NINJAS_GROUP /home/$user/.emacs.d
    chmod 770 /home/$user/.emacs.d

    # Create symlinks
    for file_or_dir in elpa init.el inits lisp custom.el; do
        su - $user -c "ln -sf $shared_emacsd/$file_or_dir /home/$user/.emacs.d/$file_or_dir"
        chown -R $user:$NINJAS_GROUP /home/$user/.emacs.d/$file_or_dir
        chmod -R 770 /home/$user/.emacs.d/$file_or_dir
    done

    # Setup user files
    su - $user -c "rm /home/$user/{recentf,history} 2>&1 >/dev/null" 2>&1 >/dev/null
    su - $user -c "touch /home/$user/.emacs.d/{recentf,history} 2>&1 >/dev/null" 2>&1 >/dev/null
    chown $user:$user /home/$user/.emacs.d/{recentf,history}
    chmod 700 /home/$user/.emacs.d/{recentf,history}
}

start_emacs_daemon() {
    local user=$1
    local display=$2
    local user_socket_dir="/home/$user/emacs-server"
    local user_socket="$user_socket_dir/server"
    local log_file=/tmp/emacs-$user.log

    mkdir -p $user_socket_dir
    chown $user:$user $user_socket_dir
    chmod 700 $user_socket_dir

    # Cleanup existing socket
    rm -f $user_socket 2>&1 >/dev/null

    # Start daemon
    rm $log_file 2>&1 >/dev/null
    su - $user -c "DISPLAY=$display emacs --daemon=$user_socket -Q > $log_file 2>&1" &

    # Verify daemon
    sleep 2
    if ! pgrep -u $user emacs >/dev/null; then
        echo "Emacs daemon failed to start for $user"
        cat $log_file
        return 1
    fi

    # Wait for socket
    local attempt=0
    while [ ! -S "$user_socket" ] && [ $attempt -lt 10 ]; do
        echo "Waiting for socket ($attempt/10)..."
        ls -l "$user_socket"* 2>/dev/null || true
        sleep 1
        ((attempt++))
    done


    # Start client with init file
    if su - $user -c "DISPLAY=$display emacsclient -c -s $user_socket --eval '(load-file \"~/.emacs.d/init.el\")'"; then
        echo -e "\n----------------------------------------"
        echo "SUCCESS: $user_socket was prepared and init.el loaded"
        echo -e "----------------------------------------\n"
        return 0
    else
        echo -e "\n----------------------------------------"
        echo "FAILED: Check error log below"
        echo -e "----------------------------------------\n"
        cat $log_file
        return 1
    fi

}


start_emacs_for_user() {
    local user=$1
    local display=$2

    setup_user_directories "$user"
    start_emacs_daemon "$user" "$display"
}


main() {
    init_environment
    for i in $(seq 1 $NINJA_N_AGENTS); do
        user="ninja-$(printf "%03d" $i)"
        start_emacs_for_user "$user" ":0"
    done
}

main

# EOF

# #!/bin/bash
# # Time-stamp: "2024-12-17 18:33:08 (ywatanabe)"
# # File: ./Ninja/.apptainer/ninja/ninja.sandbox/opt/Ninja/src/apptainer_builders/start_emacs_independently.sh

# # Check if running as root
# if [ "$(id -u)" != "0" ]; then
#     echo "This script ($0) must be run as root" >&2
#     exit 1
# fi

# source "$(dirname $0)"/ENVS.sh.src


# # Add at beginning of script
# xhost +local:root > /dev/null 2>&1

# init() {
#     # Kill existing emacs processes for all users
#     killall -9 "$NINJA_EMACS_CLIENT" 2>/dev/null || true
#     killall -9 "$NINJA_EMACS_BIN" 2>/dev/null || true
# }

# start_emacs_for_user() {
#     user=$1
#     display=$2
#     user_socket_dir="/home/$user"
#     user_socket="$user_socket_dir/server"
#     shared_emacsd=/opt/Ninja/src/apptainer_builders/shared_emacsd

#     # Permissions
#     chown root:$NINJAS_GROUP -R /home
#     chown root:$NINJAS_GROUP -R $shared_emacsd
#     chmod 777 -R $shared_emacsd

#     # Cleanup
#     rm -f $user_socket
#     su - $user -c "$NINJA_EMACS_CLIENT --eval '(kill-emacs)'" 2>/dev/null

#     # Socket Directory
#     # Creation
#     mkdir -p $user_socket_dir
#     chown -R $user:$NINJAS_GROUP $user_socket_dir
#     chmod -R 700 $user_socket_dir
#     ls $user_socket_dir -al

#     # Link shared .emacs.d
#     su - $user -c "rm -rf /home/$user/.emacs.d"
#     su - $user -c "ln -sf $shared_emacsd /home/$user/.emacs.d"

#     # Start server with explicit X11 forwarding
#     su - $user -c "DISPLAY=$DISPLAY \
    #     $NINJA_EMACS_BIN \
    #     --daemon=$user_socket \
    #     --init-directory=/home/$user/.emacs.d"

#     sleep 2

#     while [ ! -S "$user_socket" ]; do
#         echo "waiting"
#         sleep 1
#     done

#     echo ""
#     echo "----------------------------------------"
#     echo "$user_socket was prepared"
#     echo "----------------------------------------"
#     echo ""

#     # Launch client
#     # su - $user -c "DISPLAY=$display XAUTHORITY=/root/.Xauthority $NINJA_EMACS_CLIENT -c -s $user_socket"
#     su - $user -c "DISPLAY=$display $NINJA_EMACS_CLIENT -c -s $user_socket --eval '(x-focus-frame nil)' &"
#     # # su - $user -c "DISPLAY=$display $NINJA_EMACS_CLIENT -c -s $user_socket -n -a ''" &
#     # su - $user -c "DISPLAY=$display $NINJA_EMACS_CLIENT -c -n -s $user_socket" &
# }

# init
# start_emacs_for_user ninja-001 :0
# start_emacs_for_user ninja-002 :0
# start_emacs_for_user ninja-003 :0
# start_emacs_for_user ninja-004 :0


# # /opt/Ninja/src/apptainer_builders/start_emacs_independently.sh
# # EOF