#!/bin/bash

# Ask for domain name and email address at the beginning
read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME

# Update and upgrade the system
sudo apt update && sudo apt upgrade -y

# Install Apache, MariaDB, and PHP 8.2
sudo apt-get install apache2 mariadb-server php8.2 php8.2-cli php8.2-common php8.2-imap php8.2-redis php8.2-snmp php8.2-xml php8.2-mysqli php8.2-zip php8.2-mbstring php8.2-curl php8.2-gd php8.2-fpm php8.2-opcache redis-server php-redis php8.2-redis libapache2-mod-php php8.2-imagick memcached php-memcached php8.2-intl wget unzip -y

# Start and enable Apache and MariaDB
sudo systemctl start apache2
sudo systemctl enable apache2
sudo systemctl start mariadb
sudo systemctl enable mariadb

# TODO Check if this is needed.
# sudo phpenmod imagick
# sudo phpenmod intl

# Secure MariaDB Installation
# Check if MariaDB root password is already set
ROOT_PASSWORD=$(openssl rand -base64 32)
ROOT_PASSWORD_EXISTS=$(sudo mysql -u root -e "SELECT 1 FROM mysql.user WHERE user='root' AND authentication_string != '';" 2>/dev/null | grep 1)

if [ -z "$ROOT_PASSWORD_EXISTS" ]; then
    echo -e "[1;34mSecuring MariaDB installation.[0m"  # Blue
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
    send "$ROOT_PASSWORD\r"
    expect \"Re-enter new password:\"
    send "$ROOT_PASSWORD\r"
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
else
    echo -e "[1;33mMariaDB root password is already set. Skipping secure installation.[0m"  # Yellow
fi

# Check if log file exists and retrieve existing credentials if available
DB_LOG_FILE="/root/db_log.txt"
DB_KEY="$(echo ${DOMAIN_NAME} | tr '.' '_')"
if [ -f "${DB_LOG_FILE}" ] && grep -q "${DB_KEY}" "${DB_LOG_FILE}"; then 
    echo -e "\033[1;32m- Using existing database credentials from log file.\033[0m"  #Green
    DB_NAME=$(grep "${DB_KEY}_DB_NAME" ${DB_LOG_FILE} | cut -d '=' -f2)
    DB_USER=$(grep "${DB_KEY}_DB_USER" ${DB_LOG_FILE} | cut -d '=' -f2)
    DB_PASSWORD=$(grep "${DB_KEY}_DB_PASSWORD" ${DB_LOG_FILE} | cut -d '=' -f2)

    # Check if database and user exist in MySQL
    DB_EXISTS=$(sudo mysql -u root -e "SHOW DATABASES LIKE '${DB_NAME}';" | grep "${DB_NAME}")
    USER_EXISTS=$(sudo mysql -u root -e "SELECT User FROM mysql.user WHERE User='${DB_USER}';" | grep "${DB_USER}")

    if [ -n "$DB_EXISTS" ] && [ -n "$USER_EXISTS" ]; then
        echo -e "\033[1;32m- Database and user already exist. Skipping creation.\033[0m"  #Green
    else
        echo -e "\033[1;32m- Database or user does not exist. Proceeding with creation.\033[0m"  # Green
        # Create database and user
        sudo mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;"
        sudo mysql -u root -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
        sudo mysql -u root -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
        sudo mysql -u root -e "FLUSH PRIVILEGES;"
    fi
else
    # Create MySQL database and user for WordPress with randomized names and strong password
    echo -e "\033[1;32m-  Create MySQL database and user for WordPress with randomized names and strong password.\033[0m"  #Green
    DB_NAME="${DB_KEY}_db_$(openssl rand -hex 4)"
    DB_USER="${DB_KEY}_user_$(openssl rand -hex 4)"
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=')

    # Log database credentials
    echo "${DB_KEY}_DB_NAME=${DB_NAME}" >> ${DB_LOG_FILE}
    echo "${DB_KEY}_DB_USER=${DB_USER}" >> ${DB_LOG_FILE}
    echo "${DB_KEY}_DB_PASSWORD=${DB_PASSWORD}" >> ${DB_LOG_FILE}

    # Create database and user
    sudo mysql -u root -e "CREATE DATABASE \`${DB_NAME}\`;"
    sudo mysql -u root -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';" || { echo "Error: Failed to create user. Password might contain unsupported characters."; exit 1; }
    sudo mysql -u root -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
    sudo mysql -u root -e "FLUSH PRIVILEGES;"
    echo -e "\033[1;31m- DB_NAME=${DB_NAME}\033[0m"
    echo -e "\033[1;31m- DB_USER=${DB_USER}\033[0m"
    echo -e "\033[1;31m- DB_PASSWORD=${DB_PASSWORD}\033[0m"
fi

# Download and set up WordPress
cd /tmp
wget -N https://wordpress.org/latest.zip
sudo apt-get install unzip -y

if [ -d "/var/www/${DOMAIN_NAME}" ]; then
    if [ latest.zip -nt /var/www/${DOMAIN_NAME}/wp-config.php ]; then
        echo -e "[1;34mNewer WordPress version found. Proceeding with unzip.[0m"  # Blue
        unzip -o latest.zip
    else
        echo -e "[1;32mThe existing WordPress installation is already up-to-date. Skipping unzip.[0m"  # Green
    fi

    read -p "Already found WordPress site installed for ${DOMAIN_NAME}. Do you want to replace it? (y/N): " REPLACE_WORDPRESS
    REPLACE_WORDPRESS=${REPLACE_WORDPRESS:-n}
    if [[ "$REPLACE_WORDPRESS" =~ ^[Yy]$ ]]; then
        echo -e "[1;33mReplacing the existing WordPress installation...[0m"  # Yellow
        echo -e "[1;31mRemoving /var/www/${DOMAIN_NAME}[0m"  # Red
        sudo rm -rf /var/www/${DOMAIN_NAME}
        echo -e "[1;34mUnzipping WordPress to /var/www/${DOMAIN_NAME}[0m"  # Blue
        unzip -o latest.zip
        sudo rsync -av wordpress/ /var/www/${DOMAIN_NAME}/
    else
        echo -e "[1;33mSkipping WordPress installation as per user request. Continuing with other tasks.[0m"  # Yellow
    fi
else
    echo -e "[1;34mNo existing WordPress installation found. Proceeding with unzip.[0m"  # Blue
    unzip -o latest.zip
    sudo rsync -av wordpress/ /var/www/${DOMAIN_NAME}/
fi

# Set permissions for WordPress directory
echo -e "[1;34mSetting chown and permissions[0m"  # Blue
sudo chown -R www-data:www-data /var/www/${DOMAIN_NAME}
sudo chmod -R 755 /var/www/${DOMAIN_NAME}

# Move wp-config-sample.php to wp-config.php and set database info
cd /var/www/${DOMAIN_NAME}
if [ -f wp-config-sample.php ]; then
    if [ ! -f wp-config.php ]; then
        sudo cp wp-config-sample.php wp-config.php
    fi
else
    echo -e "[1;31mError: wp-config-sample.php not found.[0m"  # Red
    exit 1
fi

# Add Logic to check if wp-config.php already contains the required database credentials
# If DB INFO EXISTS in db_log.txt then match it and see if it's also in wp-config.php
if grep -q "${DB_KEY}_DB_NAME" ${DB_LOG_FILE}; then
    DB_NAME_LOG=$(grep "${DB_KEY}_DB_NAME" ${DB_LOG_FILE} | cut -d '=' -f2)
    DB_USER_LOG=$(grep "${DB_KEY}_DB_USER" ${DB_LOG_FILE} | cut -d '=' -f2)
    DB_PASSWORD_LOG=$(grep "${DB_KEY}_DB_PASSWORD" ${DB_LOG_FILE} | cut -d '=' -f2)

    # Check if wp-config.php has default values or no values
    if grep -qE "define\( 'DB_NAME', 'database_name_here' \)|define\( 'DB_NAME', '' \)" wp-config.php && \
       grep -qE "define\( 'DB_USER', 'username_here' \)|define\( 'DB_USER', '' \)" wp-config.php && \
       grep -qE "define\( 'DB_PASSWORD', 'password_here' \)|define\( 'DB_PASSWORD', '' \)" wp-config.php; then
        echo -e "[1;33mFound Default or No Values in wp-config.php.[0m"  # Yellow
        echo -e "[1;34mProceed to add DB info to wp-config.php as there are default or empty values.[0m"  # Blue
        # Add the new DB info to wp-config.php
        DB_NAME_ESCAPED=$(printf '%s' "$DB_NAME_LOG" | sed -e 's/[\/&]/\\&/g')
        DB_USER_ESCAPED=$(printf '%s' "$DB_USER_LOG" | sed -e 's/[\/&]/\\&/g')
        DB_PASSWORD_ESCAPED=$(printf '%s' "$DB_PASSWORD_LOG" | sed -e 's/[\/&]/\\&/g')
        sudo sed -i "s/define( 'DB_NAME', 'database_name_here' )/define( 'DB_NAME', '${DB_NAME_ESCAPED}' )/" wp-config.php || { echo "Error: Failed to set DB_NAME in wp-config.php"; exit 1; }
        sudo sed -i "s/define( 'DB_USER', 'username_here' )/define( 'DB_USER', '${DB_USER_ESCAPED}' )/" wp-config.php || { echo "Error: Failed to set DB_USER in wp-config.php"; exit 1; }
        sudo sed -i "s/define( 'DB_PASSWORD', 'password_here' )/define( 'DB_PASSWORD', '${DB_PASSWORD_ESCAPED}' )/" wp-config.php || { echo "Error: Failed to set DB_PASSWORD in wp-config.php"; exit 1; }
    elif grep -q "define( 'DB_NAME', '${DB_NAME_LOG}'" wp-config.php && \
         grep -q "define( 'DB_USER', '${DB_USER_LOG}'" wp-config.php && \
         grep -q "define( 'DB_PASSWORD', '${DB_PASSWORD_LOG}'" wp-config.php; then
        echo -e "[1;32mDatabase credentials already exist in wp-config.php and match the log file.[0m"  # Green
    else
        echo -e "[1;31mConflict detected between wp-config.php and db_log.txt.[0m"  # Red
        echo "Current wp-config.php values:"
        grep "define( 'DB_NAME'" wp-config.php
        grep "define( 'DB_USER'" wp-config.php
        grep "define( 'DB_PASSWORD'" wp-config.php
        echo "Log file values:"
        echo "DB_NAME=${DB_NAME_LOG}"
        echo "DB_USER=${DB_USER_LOG}"
        echo "DB_PASSWORD=${DB_PASSWORD_LOG}"
        read -p "Keep the values in wp-config.php or replace with log file values? (Keep/Replace, default is Keep): " REPLACE_VALUES
        REPLACE_VALUES=${REPLACE_VALUES:-Keep}
        if [[ "$REPLACE_VALUES" =~ ^[Rr]eplace$ ]]; then
            DB_NAME_ESCAPED=$(printf '%s' "$DB_NAME_LOG" | sed -e 's/[\/&]/\\&/g')
            DB_USER_ESCAPED=$(printf '%s' "$DB_USER_LOG" | sed -e 's/[\/&]/\\&/g')
            DB_PASSWORD_ESCAPED=$(printf '%s' "$DB_PASSWORD_LOG" | sed -e 's/[\/&]/\\&/g')
            sudo sed -i "s/define( 'DB_NAME', .*)/define( 'DB_NAME', '${DB_NAME_ESCAPED}' )/" wp-config.php
            sudo sed -i "s/define( 'DB_USER', .*)/define( 'DB_USER', '${DB_USER_ESCAPED}' )/" wp-config.php
            sudo sed -i "s/define( 'DB_PASSWORD', .*)/define( 'DB_PASSWORD', '${DB_PASSWORD_ESCAPED}' )/" wp-config.php
        else
            echo -e "[1;32mKeeping existing values in wp-config.php.[0m"  # Green
        fi
    fi
else
    # If there are no existing entries, add them
    if ! grep -q "define( 'DB_NAME', '${DB_NAME}'" wp-config.php; then
        DB_NAME_ESCAPED=$(printf '%s' "$DB_NAME" | sed -e 's/[\/&]/\\&/g')
        sudo sed -i "s/define( 'DB_NAME', 'database_name_here' )/define( 'DB_NAME', '${DB_NAME_ESCAPED}' )/" wp-config.php || { echo "Error: Failed to set DB_NAME in wp-config.php"; exit 1; }
    fi
    if ! grep -q "define( 'DB_USER', '${DB_USER}'" wp-config.php; then
        DB_USER_ESCAPED=$(printf '%s' "$DB_USER" | sed -e 's/[\/&]/\\&/g')
        sudo sed -i "s/define( 'DB_USER', 'username_here' )/define( 'DB_USER', '${DB_USER_ESCAPED}' )/" wp-config.php || { echo "Error: Failed to set DB_USER in wp-config.php"; exit 1; }
    fi
    if ! grep -q "define( 'DB_PASSWORD', '${DB_PASSWORD}'" wp-config.php; then
        DB_PASSWORD_ESCAPED=$(printf '%s' "$DB_PASSWORD" | sed -e 's/[\/&]/\\&/g')
        sudo sed -i "s/define( 'DB_PASSWORD', 'password_here' )/define( 'DB_PASSWORD', '${DB_PASSWORD_ESCAPED}' )/" wp-config.php || { echo "Error: Failed to set DB_PASSWORD in wp-config.php"; exit 1; }
    fi
fi

# Recommended W3 Total Cache?
# TODO cache php.ini 
# opcache.enable=1
# opcache.enable_cli=1
# opcache.memory_consumption=128
# opcache.interned_strings_buffer=8
# opcache.max_accelerated_files=10000

# TODO cache WP-Config.php 
# define( 'WPCACHEHOME', '/var/www/domain.com/wp-content/plugins/     PLUGIN          /' );
# define('WP_CACHE', true);

# TODO Enable redis-server 
sudo systemctl enable redis-server
sudo systemctl start redis-server

# TODO Look into sudo apt install memcached php8.2-memcached
sudo systemctl enable memcached
sudo systemctl start memcached


# Configure PHP settings for WordPress
# Check current values and only update if necessary
PHP_INI_PATH="/etc/php/8.2/apache2/php.ini"
POST_MAX_SIZE=$(grep -i '^post_max_size' $PHP_INI_PATH | awk -F' = ' '{print $2}' | tr -d 'M')
UPLOAD_MAX_FILESIZE=$(grep -i '^upload_max_filesize' $PHP_INI_PATH | awk -F' = ' '{print $2}' | tr -d 'M')
MEMORY_LIMIT=$(grep -i '^memory_limit' $PHP_INI_PATH | awk -F' = ' '{print $2}' | tr -d 'M')
MAX_EXECUTION_TIME= $(grep -i '^max_execution_time' $PHP_INI_PATH | awk -F' = ' '{print $2}' | tr -d 'M')

if [[ "${POST_MAX_SIZE}" -lt 500 ]]; then
    sudo sed -i "s/post_max_size = .*/post_max_size = 500M/" $PHP_INI_PATH
fi

if [[ "${UPLOAD_MAX_FILESIZE}" -lt 500 ]]; then
    sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = 500M/" $PHP_INI_PATH
fi

if [[ "${MEMORY_LIMIT}" -lt 256 ]]; then
    sudo sed -i "s/memory_limit = .*/memory_limit = 256M/" $PHP_INI_PATH
fi

if [[ "${MAX_EXECUTION_TIME}" -lt 256 ]]; then
    sudo sed -i "s/max_execution_time = .*/max_execution_time = 120/" $PHP_INI_PATH
fi 

# Create Apache virtual host for WordPress
VHOST_CONF_PATH="/etc/apache2/sites-available/${DOMAIN_NAME}.conf"
if [ -f "$VHOST_CONF_PATH" ]; then
    echo -e "[1;33mVirtual host configuration for ${DOMAIN_NAME} already exists.[0m"  # Yellow
    read -p "Do you want to replace it? (y/N): " REPLACE_VHOST
    REPLACE_VHOST=${REPLACE_VHOST:-n}
    if [[ "$REPLACE_VHOST" =~ ^[Yy]$ ]]; then
        echo -e "[1;33mReplacing the existing virtual host configuration for ${DOMAIN_NAME}.[0m"  # Yellow
    else
        echo -e "[1;32mKeeping the existing virtual host configuration.[0m"  # Green
    fi
else
    echo -e "[1;34mCreating virtual host configuration for ${DOMAIN_NAME}.[0m"  # Blue
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
echo -e "[1;33mCertbot symbolic link already exists, skipping creation.[0m"  # Yellow

# Obtain SSL certificate
if [ -f /etc/letsencrypt/live/${DOMAIN_NAME}/cert.pem ]; then
    echo -e "[1;32mSSL certificate for ${DOMAIN_NAME} already exists, skipping Certbot setup.[0m"  # Green
else
    EMAIL_LOG_FILE="/root/email_log.txt"
    if [ -f "${EMAIL_LOG_FILE}" ]; then
        EMAIL_ADDRESS=$(cat ${EMAIL_LOG_FILE})
    else
    # Disclaimer for A record
        echo -e "[1;33mIMPORTANT: Make sure that your domain's A record is pointed to the IP address of this Linode server before proceeding with SSL setup.[0m"  # Yellow

        read -p "Enter your email address for SSL certificate registration: " EMAIL_ADDRESS
        echo ${EMAIL_ADDRESS} > ${EMAIL_LOG_FILE}
    fi
    read -p "Do you want to install an SSL certificate for ${DOMAIN_NAME}? (Y/n): " INSTALL_SSL
    INSTALL_SSL=${INSTALL_SSL:-Y}
    if [[ "$INSTALL_SSL" =~ ^[Yy]$ ]]; then
        read -p "Do you want to add both ${DOMAIN_NAME} and www.${DOMAIN_NAME} to the SSL certificate? (Y/n): " ADD_WWW
        ADD_WWW=${ADD_WWW:-y}
        if [[ "$ADD_WWW" =~ ^[Yy]$ ]]; then
            sudo certbot --apache -d ${DOMAIN_NAME} -d www.${DOMAIN_NAME} --non-interactive --agree-tos -m ${EMAIL_ADDRESS} --redirect
        else
            sudo certbot --apache -d ${DOMAIN_NAME} --non-interactive --agree-tos -m ${EMAIL_ADDRESS} --redirect
        fi
    else
        echo -e "[1;33mSkipping SSL certificate installation as per user request.[0m"  # Yellow
    fi
fi

# Instructions if SSL setup fails
echo -e "[1;33mIf the SSL setup fails, you can manually attempt to obtain the SSL certificate by running the following command:[0m"  # Yellow
echo "sudo certbot --apache"

# Final output
echo -e "[1;32mWordPress installation complete. Please complete the setup via your web browser by navigating to http://${DOMAIN_NAME}[0m"  # Green
