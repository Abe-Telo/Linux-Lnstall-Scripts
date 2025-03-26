#!/bin/bash

# Install Fail2Ban and rsyslog on Debian 12, backup existing config, deploy recommended config, and restart.

# Update package lists and install Fail2Ban and rsyslog
echo "Updating system and installing Fail2Ban and rsyslog..."
sudo apt update
sudo apt install -y fail2ban rsyslog

# Ensure rsyslog is enabled and running
echo "Enabling and starting rsyslog service..."
sudo systemctl enable rsyslog
sudo systemctl start rsyslog

# Ensure Fail2Ban is enabled and running
echo "Enabling and starting Fail2Ban service..."
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Create or update the recidive2 filter file
echo "Creating or updating /etc/fail2ban/filter.d/recidive2.conf..."
sudo bash -c "cat > /etc/fail2ban/filter.d/recidive2.conf" <<'EOF'
[Definition]
failregex = ^.*\] Ban <HOST>$
ignoreregex =
EOF
sudo chmod 644 /etc/fail2ban/filter.d/recidive2.conf

# Create or update the recidive3 filter file
echo "Creating or updating /etc/fail2ban/filter.d/recidive3.conf..."
sudo bash -c "cat > /etc/fail2ban/filter.d/recidive3.conf" <<'EOF'
[Definition]
failregex = ^.*\] Ban <HOST>$
ignoreregex =
EOF
sudo chmod 644 /etc/fail2ban/filter.d/recidive3.conf

# Create or update the recidive4 filter file
echo "Creating or updating /etc/fail2ban/filter.d/recidive4.conf..."
sudo bash -c "cat > /etc/fail2ban/filter.d/recidive4.conf" <<'EOF'
[Definition]
failregex = ^.*\] Ban <HOST>$
ignoreregex =
EOF
sudo chmod 644 /etc/fail2ban/filter.d/recidive4.conf

CONFIG_FILE="/etc/fail2ban/jail.local"
BACKUP_FILE="/etc/fail2ban/jail.local.bak.$(date +%F-%T)"

# Get the current SSH client IP address
SSH_IP=$(echo "$SSH_CLIENT" | awk '{print $1}')
if [ -z "$SSH_IP" ]; then
    SSH_IP=$(who am i | awk '{print $5}' | sed 's/[()]//g')
fi

# Copy default configuration to jail.local if jail.local does not exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating initial configuration file from default..."
    sudo cp /etc/fail2ban/jail.conf "$CONFIG_FILE"
fi

# Backup existing configuration
if [ -f "$CONFIG_FILE" ]; then
    echo "Backing up existing configuration to $BACKUP_FILE..."
    sudo cp "$CONFIG_FILE" "$BACKUP_FILE"
fi

# Check for running risky services and prompt user
echo "Checking for active potentially insecure services..."
SERVICE_CONFIG=""
for service in vsftpd ftp telnet smb nfs rpc ssh; do
    if sudo systemctl is-active --quiet "$service"; then
        read -p "Service '$service' is active. Do you want to add Fail2Ban jail for '$service'? (y/n): " add_service
        if [[ "$add_service" =~ ^[Yy]$ ]]; then
            case "$service" in
                ssh)
                    SERVICE_CONFIG+=$'\n[sshd]\nenabled = true\nport = ssh\nlogpath = /var/log/auth.log\nmaxretry = 5\nbantime = 900\n'
                    ;;
                vsftpd|ftp)
                    SERVICE_CONFIG+=$'\n[vsftpd]\nenabled = true\nport = ftp\nlogpath = /var/log/vsftpd.log\nmaxretry = 5\nbantime = 900\n'
                    ;;
                telnet)
                    SERVICE_CONFIG+=$'\n[telnet]\nenabled = true\nport = telnet\nlogpath = /var/log/auth.log\nmaxretry = 5\nbantime = 900\n'
                    ;;
                smb)
                    SERVICE_CONFIG+=$'\n[samba]\nenabled = true\nport = samba\nlogpath = /var/log/samba/log.%m\nmaxretry = 5\nbantime = 900\n'
                    ;;
                nfs|rpc)
                    SERVICE_CONFIG+=$'\n[nfs]\nenabled = true\nport = nfs\nlogpath = /var/log/messages\nmaxretry = 5\nbantime = 900\n'
                    ;;
            esac
        fi
    fi
done

# Write Fail2Ban configuration based on user choices
echo "Writing new configuration to $CONFIG_FILE..."
sudo bash -c "cat > $CONFIG_FILE" <<EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 $SSH_IP
$SERVICE_CONFIG
[recidive2]
enabled  = true
logpath  = /var/log/fail2ban.log
findtime = 86400
maxretry = 5
bantime  = 1800

[recidive3]
enabled  = true
logpath  = /var/log/fail2ban.log
findtime = 86400
maxretry = 3
bantime  = 86400

[recidive4]
enabled  = true
logpath  = /var/log/fail2ban.log
findtime = 172800
maxretry = 1
bantime  = -1
EOF

# Restart Fail2Ban to apply changes
echo "Restarting Fail2Ban service..."
sudo systemctl restart fail2ban

# Wait a few seconds before checking status
sleep 5

# Verify service status
if sudo systemctl is-active --quiet fail2ban; then
    echo "Fail2Ban is running successfully."
else
    echo "Fail2Ban encountered an issue. Check logs with: sudo journalctl -u fail2ban"
fi

# Display Fail2Ban status
sudo fail2ban-client status

echo "Fail2Ban installation and configuration complete."
