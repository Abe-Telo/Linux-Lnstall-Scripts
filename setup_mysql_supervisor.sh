#!/bin/bash
# This script installs Supervisor, disables MySQL's systemd management,
# and sets up Supervisor to manage MySQL.
# Run this script as root (or using sudo).

# Check if the script is run as root.
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Try using sudo."
  exit 1
fi

echo "Updating package lists..."
apt-get update

echo "Installing Supervisor..."
apt-get install -y supervisor

echo "Disabling and stopping MySQL systemd service..."
systemctl disable mysql
systemctl stop mysql

echo "Creating Supervisor configuration for MySQL..."
cat <<'EOF' > /etc/supervisor/conf.d/mysql.conf
[program:mysql]
; Path to the MySQL startup command.
; Depending on your installation, you might use mysqld_safe or mysqld directly.
command=/usr/bin/mysqld_safe

; Working directory for MySQL (adjust based on your system).
directory=/var/lib/mysql

; Automatically start MySQL when Supervisor starts.
autostart=true

; Automatically restart MySQL if it crashes.
autorestart=true

; Consider exit code 0 as normal; any other code will be treated as a crash.
exitcodes=0

; Number of times to retry starting MySQL before giving up.
startretries=3

; Number of seconds MySQL must run successfully to consider the start successful.
startsecs=5

; Log file paths for stdout and stderr.
stdout_logfile=/var/log/mysql_supervisor.out.log
stderr_logfile=/var/log/mysql_supervisor.err.log

; Uncomment and adjust if MySQL needs specific environment variables.
; environment=MYSQL_HOME="/var/lib/mysql",OTHER_VAR="value"
EOF

echo "Reloading Supervisor configuration..."
supervisorctl reread
supervisorctl update

echo "Starting MySQL under Supervisor..."
supervisorctl start mysql

echo "MySQL status:"
supervisorctl status mysql
