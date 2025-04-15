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
#
# Update WP_CACHE in each site's wp-config.php based on domains in /root/db_log.txt.
#

# This snippet reads /root/db_log.txt to extract domain keys and then
# for each domain, checks if a corresponding wp-config.php file exists in
# /var/www/<domain>/wp-config.php or /var/www/<domain with underscores replaced by dots>/wp-config.php.
# If found, it checks whether "WP_CACHE" is defined. If not, it inserts 
# "define( 'WP_CACHE', true );" before the "stop editing" marker or at the end if that marker is not present.
#

DB_LOG_FILE="/root/db_log.txt"

# Ensure the DB log exists.
if [ ! -f "$DB_LOG_FILE" ]; then
    echo "Database log file $DB_LOG_FILE not found. Exiting."
    exit 1
fi

# Extract unique domain keys from the log.
# Assumes lines like "rikirose.com_DB_NAME=..." or "rikirose_com_DB_NAME=..."
domains=$(grep '_DB_NAME=' "$DB_LOG_FILE" | cut -d '=' -f1 | sed 's/_DB_NAME//' | sort -u)

echo "Found the following domain keys in $DB_LOG_FILE:"
echo "$domains"

# Loop through each domain key.
for domain in $domains; do
    # Create the dot-version by replacing underscores with dots.
    domain_dot=$(echo "$domain" | tr '_' '.')
    echo "Processing domain variants: '$domain' and '$domain_dot'"

    # Initialize an empty variable to hold the wp-config.php path.
    wp_config=""

    # Check for wp-config.php in /var/www/<domain>
    if [ -f "/var/www/${domain}/wp-config.php" ]; then
         wp_config="/var/www/${domain}/wp-config.php"
         echo "Found wp-config.php at /var/www/${domain}/wp-config.php"
    fi
    # Also check /var/www/<domain_dot>/wp-config.php; if both exist, the latter will override.
    if [ -f "/var/www/${domain_dot}/wp-config.php" ]; then
         wp_config="/var/www/${domain_dot}/wp-config.php"
         echo "Found wp-config.php at /var/www/${domain_dot}/wp-config.php"
    fi

    if [ -n "$wp_config" ]; then
         echo "Updating WP_CACHE in $wp_config"
         # If WP_CACHE isn't already defined (case-insensitive check)
         if ! grep -qi "define( *'WP_CACHE'" "$wp_config"; then
             # If the typical marker exists, insert before it.
             if grep -qi "stop editing" "$wp_config"; then
                 sudo sed -i "/[Tt]hat's all,.*stop editing/i define( 'WP_CACHE', true );" "$wp_config"
             else
                 # Otherwise append at the end.
                 echo "define( 'WP_CACHE', true );" | sudo tee -a "$wp_config" >/dev/null
             fi
         else
             echo "WP_CACHE is already defined in $wp_config, skipping."
         fi
    else
         echo "No wp-config.php found for domain variants '$domain' or '$domain_dot'."
    fi
done

echo "WP_CACHE update complete."

################################################

echo "All file checks, updates, and executions are complete."
