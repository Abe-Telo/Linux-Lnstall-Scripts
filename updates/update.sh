#!/bin/bash
#
# check_and_run_scripts.sh
#
# This script checks for two files locally:
#   1. enable_mysql_auto_restart.sh
#   2. setup-fail2ban.sh
#
# For each file, it:
#   - Downloads the remote file from GitHub if the local file does not exist,
#     or if the local file size does not match the remote file size.
#   - Ensures the file is executable.
#   - Runs the file, capturing and displaying its output and exit code.
#
# Requirements: curl, stat, mktemp
#

# Function to check, update (if needed), and run a script.
ensure_and_run() {
    local local_file="$1"
    local remote_url="$2"

    echo "----------------------------------------"
    echo "Processing ${local_file}"
    echo "Remote URL: ${remote_url}"

    # Download the remote file to a temporary file (forcing no cache)
    tmp_file=$(mktemp)
    if ! curl -s -L -H 'Cache-Control: no-cache' "${remote_url}" -o "${tmp_file}"; then
        echo "Error downloading remote file from ${remote_url}."
        rm -f "${tmp_file}"
        return 1
    fi

    # If the local file does not exist, download it.
    if [ ! -f "${local_file}" ]; then
        echo "Local file ${local_file} does not exist. Downloading..."
        cp "${tmp_file}" "${local_file}"
    else
        # Compare file sizes as a basic check for differences.
        local_size=$(stat -c%s "${local_file}")
        remote_size=$(stat -c%s "${tmp_file}")
        echo "Local file size:  ${local_size} bytes"
        echo "Remote file size: ${remote_size} bytes"
        if [ "${local_size}" -ne "${remote_size}" ]; then
            echo "Local file ${local_file} does not match the remote version. Updating..."
            cp "${tmp_file}" "${local_file}"
        else
            echo "Local file ${local_file} matches the remote version."
        fi
    fi

    # Clean up the temporary file.
    rm -f "${tmp_file}"

    # Ensure the file is executable.
    chmod +x "${local_file}"

    # Run the file.
    echo "Running ${local_file}..."
    ./"${local_file}"
    run_exit=$?
    echo "${local_file} finished with exit code ${run_exit}."
    echo "----------------------------------------"
    echo ""
}

########################################
# Main Execution: Check and Run Each Script
########################################

ensure_and_run "enable_mysql_auto_restart.sh" "https://raw.githubusercontent.com/Abe-Telo/Linux-Lnstall-Scripts/refs/heads/main/enable_mysql_auto_restart.sh"
# ensure_and_run "setup-fail2ban.sh" "https://raw.githubusercontent.com/Abe-Telo/Linux-Lnstall-Scripts/refs/heads/main/setup-fail2ban.sh"

echo "All file checks, updates, and executions are complete."
