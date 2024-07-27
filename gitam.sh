#!/usr/bin/env bash

# Enable strict mode
set -euo pipefail
IFS=$'\n\t'

# Define colors for output
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[1;36m'
readonly NC='\033[0m' # No Color

# Define log files for tracking and backup
readonly LOG_FILE="${HOME}/git_alias_usage.log"
readonly BACKUP_FILE="${HOME}/git_alias_usage_backup.log"
readonly MAX_LOG_SIZE=1024 # Max log size in KB before rotating

# Ensure the log file exists
touch "$LOG_FILE"

# Function to handle script exit
cleanup() {
    exit 0
}

# Set up trap to handle Ctrl+C and other exit signals
trap cleanup SIGINT SIGTERM EXIT

# Display the top 5 most used aliases
display_top_5() {
    sort -nr "$LOG_FILE" | uniq -c | sort -nr | head -n 5 | awk '{print $2, $1}'
}

# Rotate log file if it exceeds the max size
rotate_log_file() {
    local current_size
    current_size=$(du -k "$LOG_FILE" | cut -f1)
    if ((current_size > MAX_LOG_SIZE)); then
        echo "Rotating log file..."
        {
            echo "Top 5 most used aliases before rotation:"
            display_top_5
            echo "---"
        } >> "$BACKUP_FILE"
        : > "$LOG_FILE" # Truncate log file
    fi
}

# Execute the selected Git alias
execute_alias() {
    local command=("$@")
    local new_command=()
    local in_pretty_format=false
    local pretty_format=""

    # Process each argument in the command
    for arg in "${command[@]}"; do
        if [[ "$arg" == --pretty=format:* ]]; then
            # Start of a pretty format argument
            in_pretty_format=true
            pretty_format="${arg#*:}"
        elif $in_pretty_format && [[ "$arg" != --* ]]; then
            # Continue building pretty format argument
            pretty_format+=" $arg"
        else
            if $in_pretty_format; then
                # End of pretty format argument, add it to new command
                new_command+=("--pretty=format:$pretty_format")
                in_pretty_format=false
                pretty_format=""
            fi
            # Add non-pretty-format argument to new command
            new_command+=("$arg")
        fi
    done

    # Handle case where pretty format is the last argument
    if $in_pretty_format; then
        new_command+=("--pretty=format:$pretty_format")
    fi

    echo "Executing command: git ${new_command[*]}"
    # Use eval to properly handle the quoted pretty format
    eval "git ${new_command[*]}"
}

# Main function to run the script
main() {
    # Rotate log file if necessary
    rotate_log_file

    # Get list of Git aliases
    local alias_list
    alias_list=$(git config --get-regexp '^alias\.')

    # Check if any aliases exist
    if [[ -z "$alias_list" ]]; then
        echo "No Git aliases found."
        exit 1
    fi

    # Get top 5 most used aliases
    local top_5_aliases
    top_5_aliases=$(display_top_5 | awk '{print $1}')

    # Display available aliases
    echo "Available Git aliases:"
    while IFS= read -r alias_entry; do
        local alias_name alias_command
        alias_name=$(echo "$alias_entry" | awk '{print $1}' | sed 's/^alias\.//')
        alias_command=$(echo "$alias_entry" | cut -d' ' -f2-)
        if grep -qw "$alias_name" <<< "$top_5_aliases"; then
            echo -e "${CYAN}${alias_name}${NC} - ${YELLOW}${alias_command}${NC}"
        else
            echo -e "${alias_name} - ${YELLOW}${alias_command}${NC}"
        fi
    done <<< "$alias_list"

    # Prompt user for alias selection
    local selected_alias_name
    read -rp "Enter the alias name to execute (or 'most-used' to see the top aliases): " selected_alias_name

    if [[ -z "$selected_alias_name" ]]; then
        echo "No alias name entered. Please try again."
        exit 1
    fi



    # Find the selected alias using awk
    selected_alias=$(echo "$alias_list" | awk -v alias="alias.$selected_alias_name" '$1 == alias {print $0}')

    if [[ -z "$selected_alias" ]]; then
        echo "Alias '$selected_alias_name' not found in the list of aliases. Please try again."
        exit 1
    fi


    # Log the alias usage
    echo "$selected_alias_name" >> "$LOG_FILE"

    # Extract the command for the selected alias
    local command
    command=$(echo "$selected_alias" | cut -d' ' -f2-)

    if [[ $command == !* ]]; then
        # Handle shell command aliases
        command="${command#!}"
        echo "You selected alias: $selected_alias_name"
        echo "Alias command: $command"
        read -rp "Enter any additional arguments (or leave empty if none): " -a additional_args
        echo "Executing command: $command ${additional_args[*]}"
        eval "$command ${additional_args[*]}"
    else
        # Handle Git command aliases
        echo "You selected alias: $selected_alias_name"
        echo "Alias command: git $command"
        read -rp "Enter any additional arguments (or leave empty if none): " -a additional_args
        execute_alias $command "${additional_args[@]}"
    fi
}

# Run the main function
main
