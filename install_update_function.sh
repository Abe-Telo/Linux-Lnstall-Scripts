#!/bin/bash
#
# install_update_function.sh
#
# This script installs an update system that:
#  - Downloads update.sh from GitHub.
#  - Installs update.sh into a specified directory (default: $HOME/.local/bin).
#  - Sets up a shell function in ~/.bashrc to run update.sh manually as "run_update_scripts".
#  - Immediately runs update.sh, displaying its output in real time.
#  - Sets up a daily cron job (at 3 AM) to re-download update.sh and execute it in update mode.
#
# Usage:
#   To install:         sudo ./install_update_function.sh
#   To update (cron job): sudo ./install_update_function.sh update
#
# In update mode the script will only re-download the latest update.sh and run it.
#

set -euo pipefail

########################################
# Configuration Variables
########################################

REMOTE_URL="https://raw.githubusercontent.com/Abe-Telo/Linux-Lnstall-Scripts/refs/heads/main/updates/update.sh"
INSTALL_DIR="$HOME/.local/bin"
INSTALL_PATH="${INSTALL_DIR}/update.sh"
BASHRC="${HOME}/.bashrc"
CRON_MARKER="# update.sh daily cron job"
CRON_TIME="0 3 * * *"

########################################
# Mode Check: "update" vs "install"
########################################

# If called with "update", perform only the update action.
if [ "${1:-}" = "update" ]; then
    echo "Running in update mode: re-downloading and executing update.sh..."
    # Ensure the installation directory exists (if not already)
    if [ ! -d "${INSTALL_DIR}" ]; then
        mkdir -p "${INSTALL_DIR}"
        echo "Created directory ${INSTALL_DIR}"
    fi
    # Download the update script
    if command -v curl >/dev/null 2>&1; then
        curl -H 'Cache-Control: no-cache' -o "${INSTALL_PATH}" -L "${REMOTE_URL}"
    elif command -v wget >/dev/null 2>&1; then
        wget --no-cache -O "${INSTALL_PATH}" "${REMOTE_URL}"
    else
        echo "Error: Neither curl nor wget is installed." >&2
        exit 1
    fi
    chmod +x "${INSTALL_PATH}"
    echo "update.sh has been updated and made executable at ${INSTALL_PATH}."
    echo "Executing update.sh..."
    # Run update.sh with real-time output; capture exit code via PIPESTATUS.
    "${INSTALL_PATH}" 2>&1 | tee /dev/tty
    EXIT_CODE=${PIPESTATUS[0]}
    echo "update.sh finished with exit code ${EXIT_CODE}."
    exit ${EXIT_CODE}
fi

########################################
# Install Mode: Full installation process
########################################

echo "Starting full installation process..."

# Step 1: Create the installation directory if it doesn't exist.
if [ ! -d "${INSTALL_DIR}" ]; then
    mkdir -p "${INSTALL_DIR}"
    echo "Created directory ${INSTALL_DIR}"
fi

# Step 2: Download and install update.sh from GitHub.
echo "Downloading update.sh from ${REMOTE_URL}..."
if command -v curl >/dev/null 2>&1; then
    curl -H 'Cache-Control: no-cache' -o "${INSTALL_PATH}" -L "${REMOTE_URL}"
elif command -v wget >/dev/null 2>&1; then
    wget --no-cache -O "${INSTALL_PATH}" "${REMOTE_URL}"
else
    echo "Error: Neither curl nor wget is installed. Please install one and retry." >&2
    exit 1
fi
chmod +x "${INSTALL_PATH}"
echo "Installed update.sh to ${INSTALL_PATH} and made it executable."

# Step 3: Install the shell function to call update.sh.
# Use a here-document to define the function.
FUNCTION_DEF=$(cat <<'EOF'
# --- Added by install_update_function.sh ---
# Function to run the update script installed in ~/.local/bin
function run_update_scripts() {
    "$HOME/.local/bin/update.sh" "$@"
}
# --- End update function ---
EOF
)
# Append the function definition to ~/.bashrc if not already present.
if grep -q "function run_update_scripts()" "${BASHRC}"; then
    echo "Function run_update_scripts already exists in ${BASHRC}. Skipping function installation."
else
    echo "${FUNCTION_DEF}" >> "${BASHRC}"
    echo "Added run_update_scripts function to ${BASHRC}."
    echo "Reload your shell or run 'source ${BASHRC}' to start using it."
fi

# Step 4: Run update.sh immediately with real-time output.
echo "Running update.sh immediately..."
# Pipe output to /dev/tty using tee, so progress is visible as it happens.
"${INSTALL_PATH}" 2>&1 | tee /dev/tty
UPDATE_EXIT_CODE=${PIPESTATUS[0]}
echo "update.sh finished with exit code ${UPDATE_EXIT_CODE}."

# Step 5: Create or update the daily cron job.
# The cron job will run this script in "update" mode every day at the specified time.
CRONJOB="${CRON_TIME} $(command -v bash) $(realpath "$0") update >/dev/null 2>&1 ${CRON_MARKER}"
if crontab -l 2>/dev/null | grep -Fq "$(realpath "$0") update"; then
    echo "A cron job for update.sh already exists. Skipping addition of a new cron entry."
else
    ( crontab -l 2>/dev/null; echo "${CRONJOB}" ) | crontab -
    echo "Added cron job to run update.sh daily at 3 AM."
fi

########################################
# Final Message
########################################

echo "Installation complete."
echo "You can run the update script manually by typing: run_update_scripts"
echo "Daily cron job is scheduled to update and run update.sh automatically."
