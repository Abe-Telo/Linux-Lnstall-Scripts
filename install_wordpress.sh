#!/bin/bash

# Ask for domain name and email address at the beginning
read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME

# Update and upgrade the system
sudo apt update && sudo apt upgrade -y

# Install Apache, MariaDB, and PHP 8.2
sudo apt-get install apache2 mariadb-server php8.2 php8.2-cli php8.2-common php8.2-imap php8.2-redis php8.2-snmp php8.2-xml php8.2-mysqli php8.2-zip php8.2-mbstring php8.2-curl libapache2-mod-php wget unzip -y

# Start and enable Apache and MariaDB
sudo systemctl start apache2
sudo systemctl enable apache2
sudo systemctl start mariadb
sudo systemctl enable mariadb

# Secure MariaDB Installation
# Generate a secure root password
ROOT_PASSWORD=$(openssl rand -base64 32)

sudo apt-get install expect -y
SECURE_MYSQL=$(expect -c "
set timeout 10
spawn sudo mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"\r\"
expect \"Switch to unix_socket authentication \[Y/n\]\"
send \"n\r\"
expect \"Change the root password? \[Y/n\]\"
send \"y\r\"
expect \"New password:\"
send \"$ROOT_PASSWORD\r\"
expect \"Re-enter new password:\"
send \"$ROOT_PASSWORD\r\"
expect \"Remove anonymous users? \[Y/n\]\"
send \"y\r\"
expect \"Disallow root login remotely? \[Y/n\]\"
send \"y\r\"
expect \"Remove test database and access to it? \[Y/n\]\"
send \"y\r\"
expect \"Reload privilege tables now? \[Y/n\]\"
send \"y\r\"
expect eof
")
echo "$SECURE_MYSQL"


# Check if log file exists and retrieve existing credentials if available
DB_LOG_FILE="/root/db_log.txt"
DB_KEY="$(echo ${DOMAIN_NAME} | tr '.' '_')"
if [ -f "${DB_LOG_FILE}" ] && grep -q "${DB_KEY}" "${DB_LOG_FILE}"; then
    echo "Using existing database credentials from log file."
    DB_NAME=$(grep "${DB_KEY}_DB_NAME" ${DB_LOG_FILE} | cut -d '=' -f2)
    DB_USER=$(grep "${DB_KEY}_DB_USER" ${DB_LOG_FILE} | cut -d '=' -f2)
    DB_PASSWORD=$(grep "${DB_KEY}_DB_PASSWORD" ${DB_LOG_FILE} | cut -d '=' -f2)
else
    # Create MySQL database and user for WordPress with randomized names and strong password
    DB_NAME="${DB_KEY}_db_$(openssl rand -hex 4)"
    DB_USER="${DB_KEY}_user_$(openssl rand -hex 4)"
    DB_PASSWORD=$(openssl rand -base64 32)

    # Log database credentials
    echo "${DB_KEY}_DB_NAME=${DB_NAME}" >> ${DB_LOG_FILE}
    echo "${DB_KEY}_DB_USER=${DB_USER}" >> ${DB_LOG_FILE}
    echo "${DB_KEY}_DB_PASSWORD=${DB_PASSWORD}" >> ${DB_LOG_FILE}

    # Create database and user
    sudo mysql -u root -e "CREATE DATABASE \`${DB_NAME}\`;"
    sudo mysql -u root -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
    sudo mysql -u root -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
    sudo mysql -u root -e "FLUSH PRIVILEGES;"
fi

# Download and set up WordPress
cd /tmp
wget -N https://wordpress.org/latest.zip
sudo apt-get install unzip -y

if [ -d "/var/www/${DOMAIN_NAME}" ]; then
    if [ latest.zip -nt /var/www/${DOMAIN_NAME}/wp-config.php ]; then
        echo "Newer WordPress version found. Proceeding with unzip."
        unzip -o latest.zip
    else
        echo "The existing WordPress installation is already up-to-date. Skipping unzip."
    fi

    read -p "Already found WordPress site installed for ${DOMAIN_NAME}. Do you want to replace it? (y/N): " REPLACE_WORDPRESS
    REPLACE_WORDPRESS=${REPLACE_WORDPRESS:-n}
    if [[ "$REPLACE_WORDPRESS" =~ ^[Yy]$ ]]; then
        echo "Replacing the existing WordPress installation..."
        echo "Removing /var/www/${DOMAIN_NAME}"
        sudo rm -rf /var/www/${DOMAIN_NAME}
        echo "Unzipping WordPress to /var/www/${DOMAIN_NAME}"
        unzip -o latest.zip
    else
        echo "Skipping WordPress installation as per user request. Continuing with other tasks."
    fi
else
    echo "No existing WordPress installation found. Proceeding with unzip."
    unzip -o latest.zip
fi

sudo rsync -av wordpress/ /var/www/${DOMAIN_NAME}/


# Set permissions for WordPress directory
echo "Setting chown and permissions"
sudo chown -R www-data:www-data /var/www/${DOMAIN_NAME}
sudo chmod -R 755 /var/www/${DOMAIN_NAME}


# Move wp-config-sample.php to wp-config.php and set database info
cd /var/www/${DOMAIN_NAME}
if [ -f wp-config-sample.php ]; then
    sudo cp wp-config-sample.php wp-config.php
else
    echo "Error: wp-config-sample.php not found."
    exit 1
fi

# Add Logic to check if wp-config.php already contains the required database credentials
if ! grep -q "define( 'DB_NAME', '${DB_NAME}'" wp-config.php; then
    DB_NAME_ESCAPED=$(printf '%s
' "$DB_NAME" | sed -e 's/[\/&]/\\&/g')
    sudo sed -i "s/define( 'DB_NAME', 'database_name_here' )/define( 'DB_NAME', '${DB_NAME_ESCAPED}' )/" wp-config.php || { echo "Error: Failed to set DB_NAME in wp-config.php"; exit 1; }
fi
if ! grep -q "define( 'DB_USER', '${DB_USER}'" wp-config.php; then
    DB_USER_ESCAPED=$(printf '%s
' "$DB_USER" | sed -e 's/[\/&]/\\&/g')
    sudo sed -i "s/define( 'DB_USER', 'username_here' )/define( 'DB_USER', '${DB_USER_ESCAPED}' )/" wp-config.php || { echo "Error: Failed to set DB_USER in wp-config.php"; exit 1; }
fi
if ! grep -q "define( 'DB_PASSWORD', '${DB_PASSWORD}'" wp-config.php; then
    DB_PASSWORD_ESCAPED=$(printf '%s
' "$DB_PASSWORD" | sed -e 's/[\/&]/\\&/g')
    sudo sed -i "s/define( 'DB_PASSWORD', 'password_here' )/define( 'DB_PASSWORD', '${DB_PASSWORD_ESCAPED}' )/" wp-config.php || { echo "Error: Failed to set DB_PASSWORD in wp-config.php"; exit 1; }
fi


# Configure PHP settings for WordPress
# Check current values and only update if necessary
PHP_INI_PATH="/etc/php/8.2/apache2/php.ini"
POST_MAX_SIZE=$(grep -i '^post_max_size' $PHP_INI_PATH | awk -F' = ' '{print $2}' | tr -d 'M')
UPLOAD_MAX_FILESIZE=$(grep -i '^upload_max_filesize' $PHP_INI_PATH | awk -F' = ' '{print $2}' | tr -d 'M')
MEMORY_LIMIT=$(grep -i '^memory_limit' $PHP_INI_PATH | awk -F' = ' '{print $2}' | tr -d 'M')

if [[ "${POST_MAX_SIZE}" -lt 500 ]]; then
    sudo sed -i "s/post_max_size = .*/post_max_size = 500M/" $PHP_INI_PATH
fi

if [[ "${UPLOAD_MAX_FILESIZE}" -lt 500 ]]; then
    sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = 500M/" $PHP_INI_PATH
fi

if [[ "${MEMORY_LIMIT}" -lt 256 ]]; then
    sudo sed -i "s/memory_limit = .*/memory_limit = 256M/" $PHP_INI_PATH
fi

# Create Apache virtual host for WordPress
VHOST_CONF_PATH="/etc/apache2/sites-available/${DOMAIN_NAME}.conf"
if [ -f "$VHOST_CONF_PATH" ]; then
    echo "Virtual host configuration for ${DOMAIN_NAME} already exists."
    read -p "Do you want to replace it? (y/N): " REPLACE_VHOST
    REPLACE_VHOST=${REPLACE_VHOST:-n}
    if [[ "$REPLACE_VHOST" =~ ^[Yy]$ ]]; then
        echo "Replacing the existing virtual host configuration for ${DOMAIN_NAME}."
    else
        echo "Keeping the existing virtual host configuration."
    fi
else
    echo "Creating virtual host configuration for ${DOMAIN_NAME}."
    REPLACE_VHOST="y"
fi

if [[ "$REPLACE_VHOST" =~ ^[Yy]$ ]]; then
    sudo tee $VHOST_CONF_PATH > /dev/null <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN_NAME}
    ServerAlias www.${DOMAIN_NAME}
    DocumentRoot /var/www/${DOMAIN_NAME}

    <Directory /var/www/${DOMAIN_NAME}>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
fi

# Disable default Apache site
sudo a2dissite 000-default.conf

# Enable WordPress site and rewrite module
sudo a2ensite ${DOMAIN_NAME}.conf
sudo a2enmod rewrite
sudo systemctl reload apache2

# Install Snap and Certbot for SSL with auto-renew
sudo apt install snapd -y
sudo snap install core; sudo snap refresh core
sudo snap install --classic certbot
if [ ! -L /usr/bin/certbot ] || [ "$(readlink /usr/bin/certbot)" != "/snap/bin/certbot" ]; then
    sudo ln -sf /snap/bin/certbot /usr/bin/certbot
fi
echo "Certbot symbolic link already exists, skipping creation."


# Obtain SSL certificate
if [ -f /etc/letsencrypt/live/${DOMAIN_NAME}/cert.pem ]; then
    echo "SSL certificate for ${DOMAIN_NAME} already exists, skipping Certbot setup."
else
    EMAIL_LOG_FILE="/root/email_log.txt"
    if [ -f "${EMAIL_LOG_FILE}" ]; then
        EMAIL_ADDRESS=$(cat ${EMAIL_LOG_FILE})
    else
    # Disclaimer for A record
        echo "IMPORTANT: Make sure that your domain's A record is pointed to the IP address of this Linode server before proceeding with SSL setup."

        read -p "Enter your email address for SSL certificate registration: " EMAIL_ADDRESS
        echo ${EMAIL_ADDRESS} > ${EMAIL_LOG_FILE}
    fi
    read -p "Do you want to add both ${DOMAIN_NAME} and www.${DOMAIN_NAME} to the SSL certificate? (y/n): " ADD_WWW
    if [[ "$ADD_WWW" =~ ^[Yy]$ ]]; then
        sudo certbot --apache -d ${DOMAIN_NAME} -d www.${DOMAIN_NAME} --non-interactive --agree-tos -m ${EMAIL_ADDRESS} --redirect
    else
        sudo certbot --apache -d ${DOMAIN_NAME} --non-interactive --agree-tos -m ${EMAIL_ADDRESS} --redirect
    fi
fi

# Instructions if SSL setup fails
echo "If the SSL setup fails, you can manually attempt to obtain the SSL certificate by running the following command:"
echo "sudo certbot --apache"

# Final output
echo "WordPress installation complete. Please complete the setup via your web browser by navigating to http://${DOMAIN_NAME}"
