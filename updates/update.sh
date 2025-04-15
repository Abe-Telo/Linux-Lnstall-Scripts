#!/bin/bash
#
# check_files.sh
#
# This script checks if two local files exist and compares their file sizes
# with the corresponding remote files on GitHub.
#
# It checks:
#   1. enable_mysql_auto_restart.sh against its GitHub version.
#   2. setup-fail2ban.sh against its GitHub version.
#
# Requirements: curl, stat, mktemp
#

# Function to compare a local file with a remote file
check_file() {
    local local_file="$1"
    local remote_url="$2"
    
    echo "----------------------------------------"
    echo "Checking if ${local_file} exists and matches remote file:"
    echo "${remote_url}"
    
    if [ ! -f "${local_file}" ]; then
        echo "Local file ${local_file} does not exist."
        return 1
    fi

    # Download the remote file to a temporary file.
    tmp_file=$(mktemp)
    if ! curl -s -L "${remote_url}" -o "${tmp_file}"; then
        echo "Error downloading remote file from ${remote_url}."
        rm -f "${tmp_file}"
        return 2
    fi

    # Get file sizes for local and downloaded remote file.
    local_size=$(stat -c%s "${local_file}")
    remote_size=$(stat -c%s "${tmp_file}")

    echo "Local file size:  ${local_size} bytes"
    echo "Remote file size: ${remote_size} bytes"

    if [ "${local_size}" -eq "${remote_size}" ]; then
        echo "${local_file} exists and matches the remote file size."
    else
        echo "${local_file} exists but does NOT match the remote file size."
    fi

    # Cleanup temporary file.
    rm -f "${tmp_file}"
    echo "----------------------------------------"
    echo ""
}

########################################
# Main Script Execution
########################################

# Check enable_mysql_auto_restart.sh
check_file "enable_mysql_auto_restart.sh" "https://raw.githubusercontent.com/Abe-Telo/Linux-Lnstall-Scripts/refs/heads/main/enable_mysql_auto_restart.sh"

# Check setup-fail2ban.sh
check_file "setup-fail2ban.sh" "https://raw.githubusercontent.com/Abe-Telo/Linux-Lnstall-Scripts/refs/heads/main/setup-fail2ban.sh"

echo "File comparison checks are complete."
