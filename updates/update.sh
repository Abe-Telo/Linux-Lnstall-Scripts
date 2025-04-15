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
#   - Runs the file.
#
# For files that are known to be interactive (like setup-fail2ban.sh),
# the script will automatically pipe in the recommended (default)
# accepted prompts using the "yes" command.
#
# Requirements: curl, stat, mktemp, yes
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
    # If the file is setup-fail2ban.sh (which is interactive), auto-accept prompts.
    if [ "${local_file}" == "setup-fail2ban.sh" ]; then
        echo "Running ${local_file} with auto-accepted prompts..."
        # Pipe "yes" to automatically send "y" to any prompt.
        yes | ./"${local_file}"
        run_exit=$?
    else
        echo "Running ${local_file}..."
        ./"${local_file}"
        run_exit=$?
    fi

    echo "${local_file} finished with exit code ${run_exit}."
    echo "----------------------------------------"
    echo ""
}

########################################
# Main Execution: Check and Run Each Script
########################################

ensure_and_run "enable_mysql_auto_restart.sh" "https://raw.githubusercontent.com/Abe-Telo/Linux-Lnstall-Scripts/refs/heads/main/enable_mysql_auto_restart.sh"

ensure_and_run "setup-fail2ban.sh" "https://raw.githubusercontent.com/Abe-Telo/Linux-Lnstall-Scripts/refs/heads/main/setup-fail2ban.sh"

################################################
#
# Add WP_CACHE definition to all site's wp-config.php files
# based on entries in /root/db_log.txt.
#

DB_LOG_FILE="/root/db_log.txt"

# Check if the log file exists.
if [ ! -f "$DB_LOG_FILE" ]; then
    echo "Database log file $DB_LOG_FILE not found. Cannot process domains."
    exit 1
fi

# Extract unique domains (assumes lines like "domain.com_DB_NAME=...")
domains=$(awk -F'_' '{print $1}' "$DB_LOG_FILE" | sort -u)

echo "Found the following domains from $DB_LOG_FILE:"
for domain in $domains; do
    echo " - $domain"
done

# Loop through each domain and update wp-config.php if present.
for domain in $domains; do
    WP_CONFIG="/var/www/${domain}/wp-config.php"
    
    if [ -f "$WP_CONFIG" ]; then
        echo "Processing $WP_CONFIG for domain $domain..."
        # Check if WP_CACHE is already defined.
        if ! grep -q "define( 'WP_CACHE'" "$WP_CONFIG"; then
            echo "Adding define('WP_CACHE', true); to $WP_CONFIG"
            # Try to insert before the "That's all, stop editing" marker.
            if grep -q "That's all, stop editing" "$WP_CONFIG"; then
                sudo sed -i "/That'\''s all, stop editing/i define( 'WP_CACHE', true );" "$WP_CONFIG"
            else
                # If marker not found, append the definition at the end.
                echo "define( 'WP_CACHE', true );" | sudo tee -a "$WP_CONFIG" >/dev/null
            fi
        else
            echo "WP_CACHE is already defined in $WP_CONFIG. Skipping."
        fi
    else
        echo "wp-config.php not found in /var/www/${domain}. Skipping domain $domain."
    fi
done

echo "WP_CACHE update complete."
################################################

echo "All file checks, updates, and executions are complete."
