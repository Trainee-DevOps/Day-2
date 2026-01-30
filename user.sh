#!/bin/bash

################################################################################
# User Onboarding Automation Script
# Purpose: Automate creation and cleanup of developer accounts with proper
#          permissions, team structure, and custom configurations
# Usage: ./user_onboarding.sh [--create|--cleanup] [--csv FILE]
################################################################################

set -euo pipefail

# Configuration
DEFAULT_CSV="users.csv"
LOG_FILE="/var/log/user_management.log"
PROJECTS_BASE="/projects"
BACKUP_DIR="/var/backups/user_onboarding"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Logging Functions
################################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | sudo tee -a "${LOG_FILE}" > /dev/null
    
    case "${level}" in
        INFO)  echo -e "${BLUE}[INFO]${NC} ${message}" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} ${message}" ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} ${message}" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} ${message}" ;;
    esac
}

################################################################################
# Validation Functions
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_csv_file() {
    local csv_file="$1"
    
    if [[ ! -f "${csv_file}" ]]; then
        log ERROR "CSV file not found: ${csv_file}"
        exit 1
    fi
    
    # Check CSV format
    local header=$(head -n 1 "${csv_file}")
    if [[ "${header}" != "username,fullname,team,role" ]]; then
        log ERROR "Invalid CSV format. Expected header: username,fullname,team,role"
        exit 1
    fi
    
    log SUCCESS "CSV file validated: ${csv_file}"
}

################################################################################
# Setup Functions
################################################################################

setup_logging() {
    # Create log directory if it doesn't exist
    sudo mkdir -p "$(dirname "${LOG_FILE}")"
    sudo touch "${LOG_FILE}"
    sudo chmod 644 "${LOG_FILE}"
    
    log INFO "==================== User Onboarding Started ===================="
    log INFO "Script executed by: $(whoami)"
    log INFO "Timestamp: $(date)"
}

create_backup_dir() {
    sudo mkdir -p "${BACKUP_DIR}"
    local backup_file="${BACKUP_DIR}/backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    log INFO "Creating backup directory: ${BACKUP_DIR}"
    
    # Backup existing /etc/passwd, /etc/group, and /etc/shadow
    sudo tar -czf "${backup_file}" \
        /etc/passwd /etc/group /etc/shadow \
        2>/dev/null || true
    
    log SUCCESS "System files backed up to: ${backup_file}"
}

create_team_group() {
    local team="$1"
    
    if ! getent group "${team}" > /dev/null 2>&1; then
        sudo groupadd "${team}"
        log SUCCESS "Created team group: ${team}"
    else
        log INFO "Team group already exists: ${team}"
    fi
}

create_custom_bashrc() {
    local home_dir="$1"
    local username="$2"
    local team="$3"
    
    cat << 'EOF' | sudo tee "${home_dir}/.bashrc" > /dev/null
# Custom .bashrc for developer environment

# Colored prompt with username, hostname, and git branch
parse_git_branch() {
    git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/(\1)/'
}

# Color definitions
COLOR_RESET='\[\033[0m\]'
COLOR_USER='\[\033[1;32m\]'      # Green
COLOR_HOST='\[\033[1;34m\]'      # Blue
COLOR_PATH='\[\033[1;33m\]'      # Yellow
COLOR_GIT='\[\033[1;35m\]'       # Magenta
COLOR_TEAM='\[\033[1;36m\]'      # Cyan

# Set prompt
export PS1="${COLOR_USER}\u${COLOR_RESET}@${COLOR_HOST}\h${COLOR_RESET}:${COLOR_PATH}\w${COLOR_RESET} ${COLOR_GIT}\$(parse_git_branch)${COLOR_RESET}\n${COLOR_TEAM}[TEAM]${COLOR_RESET} \$ "

# Useful aliases
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# Project shortcuts
alias projects='cd ~/projects'
alias shared='cd /projects/TEAM/shared'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

# Environment variables
export EDITOR=vim
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoredups:erasedups

# Enable bash completion
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

# Welcome message
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Welcome USERNAME!"
echo "  Team: TEAM | Projects: ~/projects"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
EOF

    # Replace placeholders
    sudo sed -i "s/USERNAME/${username}/g" "${home_dir}/.bashrc"
    sudo sed -i "s/TEAM/${team}/g" "${home_dir}/.bashrc"
    
    sudo chown "${username}:${username}" "${home_dir}/.bashrc"
    sudo chmod 644 "${home_dir}/.bashrc"
    
    log SUCCESS "Custom .bashrc created for ${username}"
}

create_user_account() {
    local username="$1"
    local fullname="$2"
    local team="$3"
    local role="$4"
    
    log INFO "Processing user: ${username} (${fullname}) - Team: ${team}, Role: ${role}"
    
    # Create team group if it doesn't exist
    create_team_group "${team}"
    
    # Check if user already exists
    if id "${username}" &>/dev/null; then
        log WARNING "User ${username} already exists, skipping creation"
        return 0
    fi
    
    # Create user with home directory
    sudo useradd -m -s /bin/bash -c "${fullname}" -G "${team}" "${username}"
    log SUCCESS "Created user: ${username}"
    
    # Set home directory permissions (700)
    sudo chmod 700 "/home/${username}"
    log SUCCESS "Set home directory permissions (700) for ${username}"
    
    # Create custom .bashrc
    create_custom_bashrc "/home/${username}" "${username}" "${team}"
    
    # Create user's project directory structure
    local user_projects_dir="/home/${username}/projects"
    sudo mkdir -p "${user_projects_dir}"
    sudo chown "${username}:${username}" "${user_projects_dir}"
    sudo chmod 755 "${user_projects_dir}"
    log SUCCESS "Created personal projects directory: ${user_projects_dir}"
    
    # Create team project directories
    local team_base="${PROJECTS_BASE}/${team}"
    local user_team_dir="${team_base}/${username}"
    local shared_team_dir="${team_base}/shared"
    
    sudo mkdir -p "${user_team_dir}"
    sudo mkdir -p "${shared_team_dir}"
    
    # Set permissions for user's team directory (755)
    sudo chown "${username}:${team}" "${user_team_dir}"
    sudo chmod 755 "${user_team_dir}"
    log SUCCESS "Created team project directory: ${user_team_dir} (755)"
    
    # Set permissions for shared team directory (775)
    sudo chown "root:${team}" "${shared_team_dir}"
    sudo chmod 775 "${shared_team_dir}"
    sudo chmod g+s "${shared_team_dir}"  # Set SGID bit
    log SUCCESS "Created shared team directory: ${shared_team_dir} (775)"
    
    # Create README files
    create_readme_files "${username}" "${team}" "${user_projects_dir}" "${user_team_dir}"
    
    # Set initial password (require change on first login)
    echo "${username}:ChangeMe123!" | sudo chpasswd
    sudo chage -d 0 "${username}"
    log INFO "Set temporary password for ${username} (must change on first login)"
    
    log SUCCESS "User ${username} setup completed successfully"
    echo ""
}

create_readme_files() {
    local username="$1"
    local team="$2"
    local user_projects="$3"
    local team_projects="$4"
    
    # Personal projects README
    cat << EOF | sudo tee "${user_projects}/README.md" > /dev/null
# ${username}'s Personal Projects

This directory is for your personal development projects and experiments.

**Permissions:** 755 (rwxr-xr-x)
- You have full control
- Others can read and execute

## Directory Structure
- Store your personal code, scripts, and projects here
- Use version control (git) for your projects
- Keep organized with subdirectories

## Team Projects
Your team projects are located at: ${team_projects}
Shared team resources: /projects/${team}/shared
EOF

    # Team projects README
    cat << EOF | sudo tee "${team_projects}/README.md" > /dev/null
# ${username}'s Team Project Directory

Team: ${team}

**Permissions:** 755 (rwxr-xr-x)
- You have full control
- Team members can read
- Use shared directory for collaboration

## Shared Team Directory
Location: /projects/${team}/shared
Permissions: 775 (rwxrwxr-x) with SGID
- All team members can read, write, and execute
- Files created inherit team group ownership

## Best Practices
1. Use version control for all projects
2. Coordinate with team members for shared resources
3. Document your code
4. Keep the workspace clean and organized
EOF

    sudo chown "${username}:${username}" "${user_projects}/README.md"
    sudo chown "${username}:${team}" "${team_projects}/README.md"
    
    log SUCCESS "Created README files for ${username}"
}

################################################################################
# Main Create Function
################################################################################

create_users() {
    local csv_file="$1"
    
    log INFO "Starting user creation process"
    log INFO "Reading from CSV file: ${csv_file}"
    
    local user_count=0
    local success_count=0
    local fail_count=0
    
    # Skip header and process each user
    while IFS=',' read -r username fullname team role; do
        # Skip header row
        if [[ "${username}" == "username" ]]; then
            continue
        fi
        
        # Skip empty lines
        if [[ -z "${username}" ]]; then
            continue
        fi
        
        ((user_count++))
        
        if create_user_account "${username}" "${fullname}" "${team}" "${role}"; then
            ((success_count++))
        else
            ((fail_count++))
            log ERROR "Failed to create user: ${username}"
        fi
    done < "${csv_file}"
    
    log INFO "==================== Summary ===================="
    log INFO "Total users processed: ${user_count}"
    log SUCCESS "Successfully created: ${success_count}"
    if [[ ${fail_count} -gt 0 ]]; then
        log ERROR "Failed: ${fail_count}"
    fi
    log INFO "================================================="
    
    # Display created users
    display_user_summary "${csv_file}"
}

display_user_summary() {
    local csv_file="$1"
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           USER ONBOARDING SUMMARY                          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    printf "%-15s %-25s %-15s %-15s\n" "USERNAME" "FULL NAME" "TEAM" "ROLE"
    printf "%-15s %-25s %-15s %-15s\n" "===============" "=========================" "===============" "==============="
    
    while IFS=',' read -r username fullname team role; do
        if [[ "${username}" != "username" ]] && [[ -n "${username}" ]]; then
            printf "%-15s %-25s %-15s %-15s\n" "${username}" "${fullname}" "${team}" "${role}"
        fi
    done < "${csv_file}"
    
    echo ""
    echo -e "${YELLOW}Default Password:${NC} ChangeMe123!"
    echo -e "${YELLOW}Note:${NC} Users must change password on first login"
    echo ""
}

################################################################################
# Cleanup Functions
################################################################################

cleanup_users() {
    local csv_file="$1"
    
    log INFO "Starting user cleanup process"
    log WARNING "This will remove all users and their data from ${csv_file}"
    
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    if [[ "${confirm,,}" != "yes" ]]; then
        log INFO "Cleanup cancelled by user"
        exit 0
    fi
    
    local cleanup_count=0
    
    while IFS=',' read -r username fullname team role; do
        # Skip header row
        if [[ "${username}" == "username" ]]; then
            continue
        fi
        
        # Skip empty lines
        if [[ -z "${username}" ]]; then
            continue
        fi
        
        if id "${username}" &>/dev/null; then
            log INFO "Removing user: ${username}"
            
            # Remove user and home directory
            sudo userdel -r "${username}" 2>/dev/null || true
            
            # Remove team project directory
            sudo rm -rf "${PROJECTS_BASE}/${team}/${username}"
            
            ((cleanup_count++))
            log SUCCESS "Removed user: ${username}"
        else
            log INFO "User ${username} does not exist, skipping"
        fi
    done < "${csv_file}"
    
    # Clean up empty team directories and groups
    cleanup_teams "${csv_file}"
    
    log INFO "==================== Cleanup Summary ===================="
    log SUCCESS "Users removed: ${cleanup_count}"
    log INFO "========================================================"
}

cleanup_teams() {
    local csv_file="$1"
    
    # Get unique teams from CSV
    local teams=$(tail -n +2 "${csv_file}" | cut -d',' -f3 | sort -u)
    
    for team in ${teams}; do
        # Check if team directory is empty
        local team_dir="${PROJECTS_BASE}/${team}"
        if [[ -d "${team_dir}" ]]; then
            # Remove if empty or only contains shared directory
            local dir_count=$(find "${team_dir}" -mindepth 1 -maxdepth 1 -type d | wc -l)
            if [[ ${dir_count} -eq 0 ]] || [[ ${dir_count} -eq 1 && -d "${team_dir}/shared" ]]; then
                sudo rm -rf "${team_dir}"
                log INFO "Removed empty team directory: ${team_dir}"
            fi
        fi
        
        # Remove team group if no users are in it
        if getent group "${team}" > /dev/null 2>&1; then
            local group_users=$(getent group "${team}" | cut -d: -f4)
            if [[ -z "${group_users}" ]]; then
                sudo groupdel "${team}" 2>/dev/null || true
                log INFO "Removed empty team group: ${team}"
            fi
        fi
    done
}

################################################################################
# Usage and Main
################################################################################

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automate creation and cleanup of developer accounts with proper permissions.

OPTIONS:
    --create            Create users from CSV file
    --cleanup           Remove users and their data
    --csv FILE          Specify CSV file (default: users.csv)
    -h, --help          Show this help message

EXAMPLES:
    # Create users from default CSV
    sudo $0 --create

    # Create users from custom CSV
    sudo $0 --create --csv custom_users.csv

    # Cleanup all users
    sudo $0 --cleanup

CSV FORMAT:
    username,fullname,team,role
    alice_dev,Alice Johnson,backend,senior_developer
    bob_frontend,Bob Smith,frontend,developer

PERMISSIONS:
    - Home directories: 700 (rwx------)
    - Personal projects: 755 (rwxr-xr-x)
    - Team shared: 775 (rwxrwxr-x) with SGID

LOG FILE:
    ${LOG_FILE}

EOF
}

main() {
    local mode=""
    local csv_file="${DEFAULT_CSV}"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --create)
                mode="create"
                shift
                ;;
            --cleanup)
                mode="cleanup"
                shift
                ;;
            --csv)
                csv_file="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate mode
    if [[ -z "${mode}" ]]; then
        echo "Error: Please specify --create or --cleanup"
        usage
        exit 1
    fi
    
    # Check root privileges
    check_root
    
    # Setup logging
    setup_logging
    
    # Validate CSV file
    check_csv_file "${csv_file}"
    
    # Execute mode
    case "${mode}" in
        create)
            create_backup_dir
            create_users "${csv_file}"
            ;;
        cleanup)
            cleanup_users "${csv_file}"
            ;;
    esac
    
    log INFO "==================== User Onboarding Completed ===================="
}

# Run main function
main "$@"