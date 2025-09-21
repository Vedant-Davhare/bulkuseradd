#!/bin/bash

# bulkuseradd.sh - A professional script to add multiple users in bulk.

# Default values
DEFAULT_SHELL="/bin/bash"
DEFAULT_PASSWORD="Password123"
START_UID=""
LOG_FILE=""
USER_SPECIFIED_UID=0
GROUP=""

# Help message function
usage() {
    cat << EOF
Usage: bulkuseradd [OPTIONS] [USERNAMES...]
       bulkuseradd -f FILE [OPTIONS]

Options:
  -f FILE            Input file containing usernames (one per line)
  -u START_UID       Start UID for the first user, then auto-increments (default: system auto-detect)
  -g GROUP           Assign users to this secondary group (default: no secondary group)
  -s SHELL           Specify the shell for the users (default: /bin/bash)
  -p PASSWORD        Set a password for the users (default: Password123)
  -l, --log          Enable logging (default: /var/log/bulkuseradd.log)
  -h, --help         Display this help message and exit
EOF
}

# Log function
log_message() {
    if [ -n "$LOG_FILE" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    fi
}

# Validate user
validate_user() {
    if id "$1" &>/dev/null; then
        echo "User '$1' already exists, skipping..."
        log_message "User '$1' already exists, skipping."
        return 1
    fi
    return 0
}

# Find next available UID
get_next_uid() {
    local uid=${1:-$(awk -F: '$3 >= 1000 && $3 < 60000 {print $3}' /etc/passwd | sort -nr | head -n1)}
    uid=$((uid + 1))
    while getent passwd "$uid" &>/dev/null; do
        uid=$((uid + 1))
    done
    echo "$uid"
}

# Parse command-line arguments
USERS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -f)
            FILE=$2
            shift 2
            ;;
        -u)
            START_UID=$2
            USER_SPECIFIED_UID=1
            shift 2
            ;;
        -g)
            GROUP=$2
            shift 2
            ;;
        -s)
            SHELL=$2
            shift 2
            ;;
        -p)
            PASSWORD=$2
            shift 2
            ;;
        -l|--log)
            LOG_FILE="/var/log/bulkuseradd.log"
            shift
            ;;
        *)
            USERS+=("$1")
            shift
            ;;
    esac
done

# Validate input
if [ ${#USERS[@]} -eq 0 ] && [ -z "$FILE" ]; then
    echo "Error: No users provided. Use -f FILE or specify usernames."
    usage
    exit 1
fi

# Read from file if specified
if [ -n "$FILE" ]; then
    if [ ! -f "$FILE" ]; then
        echo "Error: File '$FILE' not found."
        exit 1
    fi
    while IFS= read -r USER; do
        USERS+=("$USER")
    done < "$FILE"
fi

# Auto-detect UID if not specified
if [ "$USER_SPECIFIED_UID" -eq 0 ]; then
    START_UID=$(get_next_uid)
    echo "Auto-detected starting UID: $START_UID"
fi

# Set defaults
SHELL=${SHELL:-$DEFAULT_SHELL}
PASSWORD=${PASSWORD:-$DEFAULT_PASSWORD}

# Validate secondary group (if provided)
if [ -n "$GROUP" ] && ! getent group "$GROUP" > /dev/null 2>&1; then
    echo "Group '$GROUP' does not exist. Creating the group..."
    groupadd "$GROUP" && log_message "Created group '$GROUP'."
fi

# Create users with sequential UIDs
for USER in "${USERS[@]}"; do
    validate_user "$USER" || continue

    # Assign UID
    NEW_UID="$START_UID"
    START_UID=$((NEW_UID + 1))

    # Create user with primary group as username, and secondary group if specified
    if [ -n "$GROUP" ]; then
        useradd -m -s "$SHELL" -u "$NEW_UID" -G "$GROUP" "$USER"
    else
        useradd -m -s "$SHELL" -u "$NEW_UID" "$USER"
    fi

    if [ $? -eq 0 ]; then
        echo "User '$USER' added successfully with UID $NEW_UID."
        echo "$USER:$PASSWORD" | chpasswd
        log_message "User '$USER' added with UID $NEW_UID."
    else
        echo "Error: Failed to add user '$USER'."
        log_message "Error: Failed to add user '$USER'."
    fi
done

echo "Bulk user creation process completed."

