#!/bin/bash

# Configuration Validation Function
validate_config() {
    if [ ! -f "$1" ]; then
        echo "Configuration file not found!"
        exit 1
    fi
}

# Function to check YAML validity
check_yaml() {
    if command -v yq &> /dev/null; then
        yq eval "$1" > /dev/null
    else
        echo "yq command not found, falling back to regex parsing."
        if ! [[ "$1" =~ ^[a-zA-Z0-9_]+: ]]; then
            echo "Invalid YAML format!"
            exit 1
        fi
    fi
}

# Pre-restart configuration check
pre_restart_check() {
    validate_config "config.yaml"
    check_yaml "config.yaml"
}

# Improved Port Extraction Logic
extract_port() {
    local port
    port=$(grep -Eo '([0-9]{1,5})' config.yaml | head -n 1 | tr -d '[:space:]')
    if ! [[ $port =~ ^[0-9]{1,5}$ ]] || [ "$port" -le 0 ] || [ "$port" -gt 65535 ]; then
        echo "Invalid port number extracted!"
        exit 1
    fi
    echo "$port"
}

# Directory Permission Checks
check_directory_permissions() {
    local dir=$1
    if [ ! -d "$dir" ] || [ ! -r "$dir" ]; then
        echo "Directory not found or not readable: $dir"
        exit 1
    fi
}

# Enhance systemd service startup verification
verify_service_startup() {
    local service_name=$1
    if ! systemctl is-active --quiet "$service_name"; then
        echo "Service $service_name failed to start!"
        exit 1
    fi
}

# Run pre-restart checks
pre_restart_check

# Example port usage
port=$(extract_port)
check_directory_permissions "/path/to/directory"
verify_service_startup "my_service"

# Your script logic continues here...
