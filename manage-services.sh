#!/bin/bash

# Set colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script configuration
ENV_FILE="$(pwd)/.env"
LOG_FILE="$(pwd)/docker-services.log"
DOCKER_COMPOSE_DIR="$(pwd)/docker-compose"
DRY_RUN=false

# Logging function
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$message" | tee -a "$LOG_FILE"
}

# Dry run logging
dry_log() {
    log "${BLUE}[DRY RUN] $1${NC}"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Validation checks
validate_environment() {
    dry_log "Checking environment..."
    
    # Check if running with sudo
    if [ "$EUID" -ne 0 ]; then
        if [ "$DRY_RUN" = true ]; then
            dry_log "Would require sudo privileges"
        else
            error_exit "Please run with sudo privileges"
        fi
    fi

    # Check if docker is installed and running
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is not installed"
    fi

    if ! docker info &> /dev/null; then
        error_exit "Docker daemon is not running"
    fi

    # Check files and directories
    for path in "$ENV_FILE" "$DOCKER_COMPOSE_DIR"; do
        if [ ! -e "$path" ]; then
            error_exit "Path not found: $path"
        else
            dry_log "Found: $path"
        fi
    done

    # List all compose files that would be processed
    dry_log "Found compose files:"
    find "$DOCKER_COMPOSE_DIR" -name compose.yaml -exec dirname {} \; | while read -r dir; do
        dry_log "  - $dir/compose.yaml"
    done
}

# Function to execute docker compose commands with timeout
execute_compose_command() {
    local command=$1
    local dir=$2
    local timeout=300  # 5 minutes timeout

    if [ "$DRY_RUN" = true ]; then
        dry_log "Would execute: docker compose --env-file '$ENV_FILE' $command in $dir"
        return 0
    fi

    log "${GREEN}Executing 'docker compose $command' in $dir${NC}"
    
    cd "$dir" || error_exit "Failed to change directory to $dir"
    
    # Execute command with timeout
    timeout $timeout docker compose --env-file "$ENV_FILE" $command
    local status=$?
    
    if [ $status -eq 124 ]; then
        log "${RED}Command timed out after ${timeout} seconds in $dir${NC}"
        return 1
    elif [ $status -ne 0 ]; then
        log "${RED}Command failed with status $status in $dir${NC}"
        return 1
    fi
    
    cd - > /dev/null
    return 0
}

# Main script
main() {
    > "$LOG_FILE"
    log "Starting docker services management script"
    
    # Parse arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --dry-run) DRY_RUN=true; shift ;;
            up|down|restart) command="$1"; shift ;;
            *) error_exit "Unknown parameter: $1" ;;
        esac
    done

    # Check command
    if [ -z "$command" ]; then
        error_exit "Please provide a command (up/down/restart) [--dry-run]"
    fi

    validate_environment
    
    if [ "$DRY_RUN" = true ]; then
        dry_log "Dry run completed. No changes were made."
        exit 0
    fi
    
    local failed_services=()
    
    # Process each compose file
    while IFS= read -r dir; do
        if ! execute_compose_command "$command" "$dir"; then
            failed_services+=("$dir")
        fi
    done < <(find "$DOCKER_COMPOSE_DIR" -name compose.yaml -exec dirname {} \;)
    
    # Report results
    if [ ${#failed_services[@]} -eq 0 ]; then
        log "${GREEN}All services processed successfully${NC}"
    else
        log "${YELLOW}Failed services:${NC}"
        printf '%s\n' "${failed_services[@]}" | tee -a "$LOG_FILE"
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"