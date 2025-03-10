#!/bin/bash
# Full Fail2ban Setup Script for Debian
# This script checks if Fail2ban is installed, installs it if necessary,
# backs up any existing configuration, writes a multi-level escalation
# configuration, and restarts the Fail2ban service.

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

echo "Updating package lists..."
apt-get update

# Check if Fail2ban is installed; if not, install it.
if ! dpkg -l | grep -q fail2ban; then
    echo "Fail2ban not found. Installing fail2ban..."
    apt-get install -y fail2ban
else
    echo "Fail2ban is already installed."
fi

# Optionally warn if vsftpd is not installed (since we're configuring its jail)
if ! dpkg -l | grep -q vsftpd; then
    echo "Warning: vsftpd is not installed. If you run an FTP service, consider installing vsftpd."
fi

# Define configuration file paths
CONFIG_FILE="/etc/fail2ban/jail.local"
BACKUP_FILE="/etc/fail2ban/jail.local.bak.$(date +%F-%T)"

echo "Backing up existing configuration from $CONFIG_FILE to $BACKUP_FILE..."
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo "Backup complete."
else
    echo "No existing configuration found at $CONFIG_FILE."
fi

echo "Writing new Fail2ban configuration to $CONFIG_FILE..."
cat > "$CONFIG_FILE" <<'EOF'
[DEFAULT]
# List trusted IP addresses below. Adjust as needed.
ignoreip = 127.0.0.1/8 68.195.27.141

[sshd]
enabled = true
port    = ssh
logpath = /var/log/auth.log
maxretry = 5
bantime = 900    ; 15 minutes for the first breach

[vsftpd]
enabled = true
port    = ftp
logpath = /var/log/vsftpd.log
maxretry = 5
bantime = 900    ; 15 minutes for FTP breaches

[recidive2]
enabled  = true
logpath  = /var/log/fail2ban.log
findtime = 86400       ; Look back 24 hours
maxretry = 5          ; If banned 5 times in 24 hours
bantime  = 1800       ; Ban for 30 minutes

[recidive3]
enabled  = true
logpath  = /var/log/fail2ban.log
findtime = 86400       ; 24 hours
maxretry = 3          ; If banned 3 times in 24 hours
bantime  = 86400      ; Ban for 1 day

[recidive4]
enabled  = true
logpath  = /var/log/fail2ban.log
findtime = 172800      ; Look back 48 hours for final escalation
maxretry = 1          ; If even 1 additional breach occurs in that period
bantime  = 31536000   ; Ban for 1 year (use 63072000 for 2 years if desired)
EOF

echo "New configuration written to $CONFIG_FILE."

echo "Restarting Fail2ban service..."
systemctl restart fail2ban

if [ $? -eq 0 ]; then
    echo "Fail2ban has been restarted successfully."
else
    echo "There was an error restarting Fail2ban. Please check the service status."
fi

echo "Setup complete. To check Fail2ban status, run: fail2ban-client status"
