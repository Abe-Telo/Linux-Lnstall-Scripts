#!/bin/bash
# mysql_watchdog
# enable_mysql_auto_restart.sh
# Please use this or supervisor, DO NOT RUN BOTH SCRIPTS. 
#
# This script creates a systemd override for MySQL/MariaDB to automatically restart
# the database if it crashes. It determines which service is available (MariaDB or MySQL),
# creates the appropriate override file, reloads systemd, restarts the service, and shows its status.
#
# Usage: sudo ./enable_mysql_auto_restart.sh

# Ensure the script is run as root.
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Please run with sudo."
  exit 1
fi

# Determine the service name: prefer mariadb.service (Debian 12 default) over mysql.service.
if systemctl list-unit-files | grep -q '^mariadb.service'; then
    SERVICE="mariadb"
elif systemctl list-unit-files | grep -q '^mysql.service'; then
    SERVICE="mysql"
else
    echo "Neither mariadb.service nor mysql.service was found. Exiting."
    exit 1
fi

echo "Using systemd service: $SERVICE.service"

# Define the override directory and file.
OVERRIDE_DIR="/etc/systemd/system/${SERVICE}.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"

# Ensure the override directory exists.
echo "Ensuring the override directory exists at $OVERRIDE_DIR..."
mkdir -p "$OVERRIDE_DIR"

# Create (or overwrite) the override file with auto-restart settings.
echo "Creating systemd override file to auto-restart $SERVICE..."
cat << EOF > "$OVERRIDE_FILE"
[Service]
Restart=always
RestartSec=5s
EOF

# Reload systemd daemon to apply changes.
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Restart the service so the override takes effect.
echo "Restarting $SERVICE.service..."
systemctl restart "$SERVICE"

# Display the current status of the service.
echo "Current status of $SERVICE.service:"
systemctl status "$SERVICE" --no-pager
