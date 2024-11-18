#!/bin/bash

show_help() {

PUBLIC_IP=$(curl -s -4 ifconfig.me)

echo -e "\033[1;33mPlease make sure you're pointing your DNS A Records to your server's IP address. \033[0m"
echo -e "\033[1;33mAlternatively, use http://$PUBLIC_IP (Note: Certbot will not work if the A record is not pointed correctly).\033[0m"
    
    echo 
    echo "Usage: $0 [-b] [-r] [-d] [-s] [-x] [-u] [-z] [--certbot Y/N] [--domain example.com] [--skip-system-update] [--skip-package-install] [--skip-secure-mysql] [--skip-db-creation]"
    echo ""
    echo "General Options:"
    echo "    --domain example.com       Set the domain name for the installation."
    echo "    --certbot Y/N              Install SSL certificate for domain (default: Y)"
    echo "    --view-db                  View database, user, and password from the logs."
    echo "    --view-debug-logs          View installation debug logs."
    echo "    --delete-db-info           Delete stored database and email information. Useful for troubleshooting installation issues."
    echo "    --skip-system-update       Skip updating and upgrading the system"
    echo "    --skip-package-install     Skip installing required packages"
    echo "    --skip-secure-mysql        Skip securing the MariaDB installation"
    echo "    --skip-db-creation         Skip database creation for WordPress"
    echo "    --install-all              Sets the script to install evrything"
    echo ""
    echo "Backup Options:"
    echo "    -b                         Create a new backup"
    echo "    -r                         Replace old backup"
    echo "    -d                         Delete old backups"
    echo "    -s                         Skip backup operation"
    echo "    -x                         Restore from a backup"
    echo "    -u                         Unzip a backup folder"
    echo "    -z                         Delete unzipped folders"
    echo "Examples:"
    echo "sudo $0 -s --certbot N --domain example.com --skip-system-update --skip-package-install --skip-secure-mysql --skip-db-creation"
}

#CERTBOT_INSTALL="Y"  # Default to Yes for SSL installation

while getopts ":brdsxuz-:" opt; do
    case $opt in
        b) BACKUP_ACTION="b" ;;
        r) BACKUP_ACTION="r" ;;
        d) BACKUP_ACTION="d" ;;
        s) BACKUP_ACTION="s" ;;
        x) BACKUP_ACTION="x" ;;
        u) BACKUP_ACTION="u" ;;
        z) BACKUP_ACTION="z" ;;
        -)
            case "${OPTARG}" in
                certbot)
                    CERTBOT_INSTALL="${!OPTIND}"; OPTIND=$((OPTIND + 1))
                    ;;
			    install-all)
				    BACKUP_ACTION="b"
                    SKIP_SYSTEM_UPDATE="false"
					SKIP_PACKAGE_INSTALL="false"
					SKIP_SECURE_MYSQL="false"
					SKIP_DB_CREATION="false"
                    ;;
					
                domain)
                    DOMAIN_NAME="${!OPTIND}"; OPTIND=$((OPTIND + 1))
                    ;;
                skip-system-update)
                    SKIP_SYSTEM_UPDATE="true"
                    ;;
                skip-package-install)
                    SKIP_PACKAGE_INSTALL="true"
                    ;;
                skip-secure-mysql)
                    SKIP_SECURE_MYSQL="true"
                    ;;
                skip-db-creation)
                    SKIP_DB_CREATION="true"
                    ;;
                view-db)
                    cat /root/db_log.txt /root/email_log.txt
                    exit 0
                    ;;
                view-debug-logs)
                    cat /var/log/wp_setup.log
                    exit 0
                    ;;
                delete-db-info)
                    rm -f /root/db_log.txt /root/email_log.txt
                    echo -e "\033[1;32mDatabase and email information deleted successfully.\033[0m"
                    exit 0
                    ;;
                *)
                    echo -e "\033[1;31mInvalid option: --$OPTARG\033[0m\n"  # Red
                    show_help
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo -e "\033[1;31mInvalid option: -$OPTARG\033[0m\n"  # Red
            show_help
            exit 1
            ;;
    esac
done

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo -e "\033[1;31mPlease run as root. Exiting.\033[0m\n"  # Red
  exit 1
fi

# Log file for tracking actions
LOG_FILE="/var/log/wp_setup.log"
echo -e "All log files will be stored in ${LOG_FILE}"
exec > >(tee -a <(while IFS= read -r line; do echo "$(date): $line"; done >> "$LOG_FILE")) 2>&1 
#exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE.err" >&2)

# Function to validate domain name
validate_domain_name() {
  if [[ ! "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
    echo -e "\033[1;31mInvalid domain name. Exiting.\033[0m\n"  # Red
    exit 1
  fi
}

# Ask for domain name if not provided
if [ -z "$DOMAIN_NAME" ]; then
    echo -e "\033[1;31m- For more information on how to use this script, please run $0 -h. \033[0m"
    read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
    validate_domain_name "$DOMAIN_NAME"
fi

# Global Directory
BACKUP_TIMESTAMP=$(date +%Y%m%d%H%M%S)
UNIQUE_ID=$(command -v uuidgen >/dev/null 2>&1 && uuidgen || echo $RANDOM)
BACKUP_DIR="/var/backups/${DOMAIN_NAME}_${BACKUP_TIMESTAMP}_${UNIQUE_ID}.tar.gz"
BACKUP_FILES=(/var/backups/${DOMAIN_NAME}_*.tar.gz)
DB_LOG_FILE="/root/db_log.txt"
DB_KEY="$(echo ${DOMAIN_NAME} | tr '.' '_')"

# Function to create a new backup
create_backup() { 
    echo -e "\033[1;34mCreating backup of existing WordPress installation at ${BACKUP_DIR}\033[0m\n"  # Blue
    sudo tar -czf "${BACKUP_DIR}" -C /var/www "${DOMAIN_NAME}" || { echo -e "\033[1;31mFailed to create backup. Exiting.\033[0m\n"; exit 1; }
    echo -e "\033[1;32mBackup created successfully.\033[0m\n"  # Green
}

# Update and upgrade the system
if [ "$SKIP_SYSTEM_UPDATE" != "true" ]; then
    sudo apt-get update && sudo apt-get upgrade -y || { echo -e "\033[1;31mSystem update/upgrade failed. Exiting.\033[0m\n"; exit 1; }
else
    echo -e "\033[1;33mSkipping system update and upgrade as per user request.\033[0m\n"  # Yellow
fi

# Install Apache, MariaDB, and PHP 8.2
if [ "$SKIP_PACKAGE_INSTALL" != "true" ]; then
    PACKAGES=(apache2 mariadb-server php8.2 php8.2-cli php8.2-common php8.2-imap php8.2-redis php8.2-snmp php8.2-xml php8.2-mysqli php8.2-zip php8.2-mbstring php8.2-curl libapache2-mod-php wget unzip expect)
    sudo apt-get install -y "${PACKAGES[@]}" || { echo -e "\033[1;31mFailed to install required packages. Exiting.\033[0m\n"; exit 1; }
else
    echo -e "\033[1;33mSkipping package installation as per user request.\033[0m\n"  # Yellow
fi

# Start and enable Apache and MariaDB
sudo systemctl start apache2 || { echo -e "\033[1;31mFailed to start Apache. Exiting.\033[0m\n"; exit 1; }
sudo systemctl enable apache2 || { echo -e "\033[1;31mFailed to enable Apache. Exiting.\033[0m\n"; exit 1; }
sudo systemctl start mariadb || { echo -e "\033[1;31mFailed to start MariaDB. Exiting.\033[0m\n"; exit 1; }
sudo systemctl enable mariadb || { echo -e "\033[1;31mFailed to enable MariaDB. Exiting.\033[0m\n"; exit 1; }

# Secure MariaDB Installation
ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=')
ROOT_PASSWORD_EXISTS=$(sudo mysql -u root -e "SELECT 1 FROM mysql.user WHERE user='root' AND authentication_string != '';" 2>/dev/null | grep 1)

# Secure MariaDB Installation
if [ "$SKIP_SECURE_MYSQL" != "true" ]; then
    ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=')
    ROOT_PASSWORD_EXISTS=$(sudo mysql -u root -e "SELECT 1 FROM mysql.user WHERE user='root' AND authentication_string != '';" 2>/dev/null | grep 1)

    if [ -z "$ROOT_PASSWORD_EXISTS" ]; then
        echo -e "\033[1;34mSecuring MariaDB installation.\033[0m\n"  # Blue
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
        send \"$ROOT_PASSWORD\r"
        expect \"Re-enter new password:\"
        send \"$ROOT_PASSWORD\r"
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
        echo -e "\033[1;33mMariaDB root password is already set. Skipping secure installation.\033[0m\n"  # Yellow
    fi
else
    echo -e "\033[1;33mSkipping MariaDB secure installation as per user request.\033[0m\n"  # Yellow
fi

# Check if log file exists and retrieve existing credentials if available
if [ "$SKIP_DB_CREATION" != "true" ]; then
    if [ -f "${DB_LOG_FILE}" ] && grep -q "${DB_KEY}" "${DB_LOG_FILE}"; then 
        echo -e "\033[1;32m- Using existing database credentials from log file.\033[0m\n"  #Green
        DB_NAME=$(grep "${DB_KEY}_DB_NAME" ${DB_LOG_FILE} | cut -d '=' -f2)
        DB_USER=$(grep "${DB_KEY}_DB_USER" ${DB_LOG_FILE} | cut -d '=' -f2)
        DB_PASSWORD=$(grep "${DB_KEY}_DB_PASSWORD" ${DB_LOG_FILE} | cut -d '=' -f2)

        # Check if database and user exist in MySQL
        DB_EXISTS=$(sudo mysql -u root -e "SHOW DATABASES LIKE '${DB_NAME}';" | grep "${DB_NAME}")
        USER_EXISTS=$(sudo mysql -u root -e "SELECT User FROM mysql.user WHERE User='${DB_USER}';" | grep "${DB_USER}")

        if [ -n "$DB_EXISTS" ] && [ -n "$USER_EXISTS" ]; then
            echo -e "\033[1;32m- Database and user already exist. Skipping creation.\033[0m\n"  #Green
        else
            echo -e "\033[1;32m- Database or user does not exist. Proceeding with creation.\033[0m\n"  # Green
            # Create database and user
            sudo mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;" || { echo -e "\033[1;31mFailed to create database. Exiting.\033[0m\n"; exit 1; }
            sudo mysql -u root -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';" || { echo -e "\033[1;31mFailed to create user. Exiting.\033[0m\n"; exit 1; }
            sudo mysql -u root -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';" || { echo -e "\033[1;31mFailed to grant privileges. Exiting.\033[0m\n"; exit 1; }
            sudo mysql -u root -e "FLUSH PRIVILEGES;" || { echo -e "\033[1;31mFailed to flush privileges. Exiting.\033[0m\n"; exit 1; }
        fi
    else
        # Create MySQL database and user for WordPress with randomized names and strong password
        echo -e "\033[1;32m- Create MySQL database and user for WordPress with randomized names and strong password.\033[0m\n"  #Green
        DB_NAME="${DB_KEY}_db_$(openssl rand -hex 4)"
        DB_USER="${DB_KEY}_user_$(openssl rand -hex 4)"
        DB_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=')

        # Log database credentials
        echo "${DB_KEY}_DB_NAME=${DB_NAME}" >> ${DB_LOG_FILE}
        echo "${DB_KEY}_DB_USER=${DB_USER}" >> ${DB_LOG_FILE}
        echo "${DB_KEY}_DB_PASSWORD=${DB_PASSWORD}" >> ${DB_LOG_FILE}

        # Create database and user
        sudo mysql -u root -e "CREATE DATABASE \`${DB_NAME}\`;" || { echo -e "\033[1;31mFailed to create database. Exiting.\033[0m\n"; exit 1; }
        sudo mysql -u root -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';" || { echo "Error: Failed to create user. Password might contain unsupported characters."; exit 1; }
        sudo mysql -u root -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';" || { echo -e "\033[1;31mFailed to grant privileges. Exiting.\033[0m\n"; exit 1; }
        sudo mysql -u root -e "FLUSH PRIVILEGES;" || { echo -e "\033[1;31mFailed to flush privileges. Exiting.\033[0m\n"; exit 1; }
        echo -e "\033[1;31m- DB_NAME=${DB_NAME}\033[0m\n"
        echo -e "\033[1;31m- DB_USER=${DB_USER}\033[0m\n"
        echo -e "\033[1;31m- DB_PASSWORD=${DB_PASSWORD}\033[0m\n"
    fi
else
    echo -e "\033[1;33mSkipping database creation as per user request.\033[0m\n"  # Yellow
fi

# If no arguments are provided, prompt the user
if [ -z "$BACKUP_ACTION" ]; then
    # List existing backups and ask user what to do
    echo -e "\033[1;34mChecking for existing backups...\033[0m\n"  # Blue
        if [ ${#BACKUP_FILES[@]} -gt 0 ]; then
        echo -e "\033[1;33mExisting backups found:\033[0m\n"  # Yellow
        echo -e "\033[1;34m-------------------------------------------\033[0m\n"
        printf " %-5s %-50s\n" "No." "Backup File"
        echo -e "\033[1;34m-------------------------------------------\033[0m\n"
        for i in "${!BACKUP_FILES[@]}"; do
            printf " %-5s %-50s\n" "$((i+1))" "${BACKUP_FILES[$i]}"
        done
        echo -e "\033[1;34m-------------------------------------------\033[0m\n"

        read -p "Do you want to (b)ackup, (r)eplace old backup, (d)elete old backups, (s)kip, (x)Restore from a backup, (u) Unzip Backup folder, or (z)Delete unzip folders? (b/r/d/s/x/u/z, default is b): " BACKUP_ACTION
        BACKUP_ACTION=${BACKUP_ACTION,,}  # Convert to lowercase
        BACKUP_ACTION=${BACKUP_ACTION:-b}
    else
        echo -e "\033[1;33mNo existing backups found. Proceeding with new backup creation.\033[0m\n"  # Yellow
        BACKUP_ACTION="b"
    fi
fi

# Validate user input
if ! [[ "$BACKUP_ACTION" =~ ^(b|r|d|s|u|x|z)$ ]]; then
    echo -e "\033[1;31mInvalid option. Exiting.\033[0m\n"  # Red
    exit 1
fi

# Perform the action based on the user input
case "$BACKUP_ACTION" in
    b)
        echo -e "\033[1;34mCreating a new backup...\033[0m\n"  # Blue
        create_backup
        ;;

    r)
        echo -e "\033[1;33mReplacing the latest backup...\033[0m\n"  # Yellow
        if [ ${#BACKUP_FILES[@]} -gt 0 ]; then
            LATEST_BACKUP="${BACKUP_FILES[${#BACKUP_FILES[@]}-1]}"
            if [ -f "$LATEST_BACKUP" ]; then
                echo -e "\033[1;34mRemoving the latest backup: $LATEST_BACKUP\033[0m\n"  # Blue
                sudo rm -f "$LATEST_BACKUP" || { echo -e "\033[1;31mFailed to remove old backup. Exiting.\033[0m\n"; exit 1; }
                echo -e "\033[1;32mOld backup removed successfully.\033[0m\n"  # Green
            else
                echo -e "\033[1;31mNo valid backup file found to remove: $LATEST_BACKUP. Skipping removal.\033[0m\n"
            fi
        else
            echo -e "\033[1;31mNo backups available to replace. Exiting.\033[0m\n"
            exit 1
        fi

        # Create a new backup after removing the old one
        create_backup
        ;;
    d)
        echo -e "\033[1;34mPlease select the backups you want to delete:\033[0m\n"  # Blue
        for i in "${!BACKUP_FILES[@]}"; do
            read -p "Delete backup ${BACKUP_FILES[$i]}? (y/n, default is n): " DELETE_BACKUP
            DELETE_BACKUP=${DELETE_BACKUP,,}  # Convert to lowercase
            DELETE_BACKUP=${DELETE_BACKUP:-n}
            if [[ "$DELETE_BACKUP" =~ ^[y]$ ]]; then
                if [ -f "${BACKUP_FILES[$i]}" ]; then
                    sudo rm -f "${BACKUP_FILES[$i]}" || { echo -e "\033[1;31mFailed to delete backup ${BACKUP_FILES[$i]}.\033[0m\n"; }
                else
                    echo -e "\033[1;31mNo valid backup file found to delete: ${BACKUP_FILES[$i]}.\033[0m\n"
                fi
            fi
        done
        ;;
    u)
        echo -e "\033[1;34mPlease select the backup you want to unzip:\033[0m\n"  # Blue
        for i in "${!BACKUP_FILES[@]}"; do
            read -p "Unzip backup ${BACKUP_FILES[$i]}? (y/n, default is n): " UNZIP_BACKUP
            UNZIP_BACKUP=${UNZIP_BACKUP,,}  # Convert to lowercase
            UNZIP_BACKUP=${UNZIP_BACKUP:-n}
            if [[ "$UNZIP_BACKUP" =~ ^[y]$ ]]; then
                UNZIP_DIR="/var/backups/${DOMAIN_NAME}_unzip_$(basename ${BACKUP_FILES[$i]} .tar.gz)"
                sudo mkdir -p "$UNZIP_DIR" && sudo tar -xzf "${BACKUP_FILES[$i]}" -C "$UNZIP_DIR" || { echo -e "\033[1;31mFailed to unzip backup ${BACKUP_FILES[$i]}.\033[0m\n"; }
                echo -e "\033[1;32mBackup ${BACKUP_FILES[$i]} unzipped successfully to $UNZIP_DIR.\033[0m\n"  # Green
            fi
        done
        ;;
    s)
        echo -e "\033[1;33mSkipping backup operation.\033[0m\n"  # Yellow
        ;;
    x)
        echo -e "\033[1;34mPlease select the backup you want to restore:\033[0m\n"  # Blue
        for i in "${!BACKUP_FILES[@]}"; do
            read -p "Restore backup ${BACKUP_FILES[$i]}? (y/n, default is n): " RESTORE_BACKUP
            RESTORE_BACKUP=${RESTORE_BACKUP,,}  # Convert to lowercase
            RESTORE_BACKUP=${RESTORE_BACKUP:-n}
            if [[ "$RESTORE_BACKUP" =~ ^[y]$ ]]; then
                sudo tar -xzf "${BACKUP_FILES[$i]}" -C /var/www --checkpoint=.100 || { echo -e "\033[1;31mFailed to restore backup ${BACKUP_FILES[$i]}.\033[0m\n"; exit 1; }
                echo -e "\033[1;32mBackup ${BACKUP_FILES[$i]} restored successfully.\033[0m\n"  # Green
            fi
        done
        ;;
    z)
        echo -e "\033[1;34mPlease select the unzip folders you want to delete:\033[0m\n"  # Blue
        UNZIP_DIRS=(/var/backups/${DOMAIN_NAME}_unzip_*)
        if [ ${#UNZIP_DIRS[@]} -gt 0 ] && [ -d "${UNZIP_DIRS[0]}" ]; then
            for i in "${!UNZIP_DIRS[@]}"; do
                read -p "Delete unzip folder ${UNZIP_DIRS[$i]}? (y/n, default is n): " DELETE_UNZIP
                DELETE_UNZIP=${DELETE_UNZIP,,}  # Convert to lowercase
                DELETE_UNZIP=${DELETE_UNZIP:-n}
                if [[ "$DELETE_UNZIP" =~ ^[y]$ ]]; then
                    if [ -d "${UNZIP_DIRS[$i]}" ]; then
                        sudo rm -rf "${UNZIP_DIRS[$i]}" || { echo -e "\033[1;31mFailed to delete unzip folder ${UNZIP_DIRS[$i]}.\033[0m\n"; }
                    else
                        echo -e "\033[1;31mNo valid unzip folder found to delete: ${UNZIP_DIRS[$i]}.\033[0m\n"
                    fi
                fi
            done
        else
            echo -e "\033[1;33mNo unzip folders found to delete.\033[0m\n"  # Yellow
        fi
        ;;
    *)
        echo -e "\033[1;31mInvalid option. Exiting.\033[0m\n"  # Red
        exit 1
        ;;
esac

# WordPress Installation Logic
if [ -d "/var/www/${DOMAIN_NAME}" ]; then
    read -t 30 -p "Already found WordPress site installed for ${DOMAIN_NAME}. Do you want to replace it? (y/N): " REPLACE_WORDPRESS
    REPLACE_WORDPRESS=${REPLACE_WORDPRESS,,}  # Convert to lowercase
    REPLACE_WORDPRESS=${REPLACE_WORDPRESS:-n}
    if [[ "$REPLACE_WORDPRESS" =~ ^[y]$ ]]; then
        echo -e "\033[1;33mReplacing the existing WordPress installation...\033[0m\n"  # Yellow
        sudo rm -rf /var/www/${DOMAIN_NAME} || { echo -e "\033[1;31mFailed to remove existing WordPress directory. Exiting.\033[0m\n"; exit 1; }
    else
        echo -e "\033[1;33mSkipping WordPress installation as per user request. Continuing with other tasks.\033[0m\n"  # Yellow
    fi
fi

# Download WordPress if latest.tar.gz is missing or corrupted
if [ ! -f "latest.tar.gz" ]; then
    echo -e "\033[1;34mDownloading WordPress package...\033[0m\n"  # Blue
    wget https://wordpress.org/latest.tar.gz -O latest.tar.gz || { echo -e "\033[1;31mFailed to download WordPress. Exiting.\033[0m\n"; exit 1; }
fi

# Validate the downloaded tar file to ensure it's not corrupted
if ! tar -tzf latest.tar.gz > /dev/null 2>&1; then
    echo -e "\033[1;31mThe WordPress archive seems to be corrupted. Exiting.\033[0m\n"  # Red
    exit 1
fi

# Extract and install WordPress
if [ ! -d "/var/www/${DOMAIN_NAME}" ]; then
    echo -e "\033[1;34mExtracting WordPress to /tmp/wordpress_unzip\033[0m\n"  # Blue
    mkdir -p /tmp/wordpress_unzip
    sudo tar -xzf latest.tar.gz -C /tmp/wordpress_unzip --checkpoint=.100 || { echo -e "\033[1;31mFailed to extract WordPress. Exiting.\033[0m\n"; exit 1; }
    #tar -xzvf latest.tar.gz -C /tmp/wordpress_unzip || { echo -e "\033[1;31mFailed to extract WordPress. Exiting.\033[0m\n"; exit 1; }

    # Check if the extraction was successful
    if [ ! -d "/tmp/wordpress_unzip/wordpress" ]; then
        echo -e "\033[1;31mFailed to extract WordPress files properly. Exiting.\033[0m\n"  # Red
        exit 1
    fi

    echo -e "\033[1;34m > DONE. \033[0m\n"  # Blue
    echo -e "\033[1;34m- Rsync WordPress files to /var/www/${DOMAIN_NAME} \033[0m\n"  # Blue
    
    sudo rsync -ah --ignore-errors --partial /tmp/wordpress_unzip/wordpress/ /var/www/${DOMAIN_NAME}/ || { echo -e "\033[1;31mFailed to copy WordPress files. Exiting.\033[0m\n"; exit 1; }
    sudo rm -rf /tmp/wordpress_unzip
fi

# Set permissions for WordPress directory
echo -e "\033[1;34mSetting chown and permissions\033[0m\n"  # Blue
sudo chown -R www-data:www-data /var/www/${DOMAIN_NAME} || { echo -e "\033[1;31mFailed to set ownership for WordPress directory. Exiting.\033[0m\n"; exit 1; }
sudo chmod -R 750 /var/www/${DOMAIN_NAME} || { echo -e "\033[1;31mFailed to set permissions for WordPress directory. Exiting.\033[0m\n"; exit 1; }

# Move wp-config-sample.php to wp-config.php and set database info
cd /var/www/${DOMAIN_NAME}
if [ -f wp-config-sample.php ]; then
    if [ ! -f wp-config.php ]; then
        sudo cp wp-config-sample.php wp-config.php || { echo -e "\033[1;31mFailed to copy wp-config-sample.php to wp-config.php. Exiting.\033[0m\n"; exit 1; }
    fi
else
    echo -e "\033[1;31mError: wp-config-sample.php not found. Exiting.\033[0m\n"  # Red
    exit 1
fi

# Adding a cleanup trap to remove temporary directories on script exit
trap "sudo rm -rf /tmp/wordpress_unzip; echo -e '\033[1;34mCleanup complete.\033[0m\n'" EXIT

# Configure PHP settings for WordPress
PHP_INI_PATH="/etc/php/8.2/apache2/php.ini"
POST_MAX_SIZE=$(grep -i '^post_max_size' $PHP_INI_PATH | awk -F' = ' '{print $2}' | tr -d 'M')
UPLOAD_MAX_FILESIZE=$(grep -i '^upload_max_filesize' $PHP_INI_PATH | awk -F' = ' '{print $2}' | tr -d 'M')
MEMORY_LIMIT=$(grep -i '^memory_limit' $PHP_INI_PATH | awk -F' = ' '{print $2}' | tr -d 'M')

if [[ "${POST_MAX_SIZE}" -lt 500 ]]; then
    sudo sed -i "s/post_max_size = .*/post_max_size = 500M/" $PHP_INI_PATH || { echo -e "\033[1;31mFailed to set post_max_size. Exiting.\033[0m\n"; exit 1; }
fi

if [[ "${UPLOAD_MAX_FILESIZE}" -lt 500 ]]; then
    sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = 500M/" $PHP_INI_PATH || { echo -e "\033[1;31mFailed to set upload_max_filesize. Exiting.\033[0m\n"; exit 1; }
fi

if [[ "${MEMORY_LIMIT}" -lt 256 ]]; then
    sudo sed -i "s/memory_limit = .*/memory_limit = 256M/" $PHP_INI_PATH || { echo -e "\033[1;31mFailed to set memory_limit. Exiting.\033[0m\n"; exit 1; }
fi

# Create Apache virtual host for WordPress
VHOST_CONF_PATH="/etc/apache2/sites-available/${DOMAIN_NAME}.conf"
if [ -f "$VHOST_CONF_PATH" ]; then
    echo -e "\033[1;33mVirtual host configuration for ${DOMAIN_NAME} already exists.\033[0m\n"  # Yellow
    read -p "Do you want to replace it? (y/N): " REPLACE_VHOST
    REPLACE_VHOST=${REPLACE_VHOST,,}  # Convert to lowercase
    REPLACE_VHOST=${REPLACE_VHOST:-n}
    if [[ "$REPLACE_VHOST" =~ ^[y]$ ]]; then
        echo -e "\033[1;33mReplacing the existing virtual host configuration for ${DOMAIN_NAME}.\033[0m\n"  # Yellow
    else
        echo -e "\033[1;32mKeeping the existing virtual host configuration.\033[0m\n"  # Green
    fi
else
    echo -e "\033[1;34mCreating virtual host configuration for ${DOMAIN_NAME}.\033[0m\n"  # Blue
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
sudo a2dissite 000-default.conf || { echo -e "\033[1;31mFailed to disable default Apache site. Exiting.\033[0m\n"; exit 1; }

# Enable WordPress site and rewrite module
sudo a2ensite ${DOMAIN_NAME}.conf
sudo a2enmod rewrite
sudo systemctl reload apache2

# Install Snap and Certbot for SSL with auto-renew
sudo apt-get install snapd -y
sudo snap install core; sudo snap refresh core
sudo snap install --classic certbot
if [ ! -L /usr/bin/certbot ] || [ "$(readlink /usr/bin/certbot)" != "/snap/bin/certbot" ]; then
    sudo ln -sf /snap/bin/certbot /usr/bin/certbot
fi
echo -e "\033[1;33m- Certbot symbolic link already exists, skipping creation.\033[0m\n"  # Yellow

# Obtain SSL certificate
if [ -f /etc/letsencrypt/live/${DOMAIN_NAME}/cert.pem ]; then
    echo -e "\033[1;33m- SSL certificate for ${DOMAIN_NAME} already exists, skipping Certbot setup.\033[0m\n"  # Green
else
    EMAIL_LOG_FILE="/root/email_log.txt"
    if [ -f "${EMAIL_LOG_FILE}" ]; then
        EMAIL_ADDRESS=$(cat ${EMAIL_LOG_FILE})
    else
        # Disclaimer for A record
        echo -e "\033[1;33mIMPORTANT: Make sure that your domain's A record is pointed to the IP address of this Linode server before proceeding with SSL setup.\033[0m\n"  # Yellow
        read -p "Enter your email address for SSL certificate registration: " EMAIL_ADDRESS
        echo "${EMAIL_ADDRESS}" > "${EMAIL_LOG_FILE}"
    fi

    # Check if CERTBOT_INSTALL is set or prompt the user
    if [[ -z "$CERTBOT_INSTALL" ]]; then
        read -p "Do you want to install an SSL certificate for ${DOMAIN_NAME}? (Y/n): " INSTALL_SSL
        CERTBOT_INSTALL=${INSTALL_SSL:-Y}
    fi

    if [[ "$CERTBOT_INSTALL" =~ ^[Yy]$ ]]; then
        # Automatically proceed with installing SSL without additional prompts
        ADD_WWW="Y"
    elif [[ "$CERTBOT_INSTALL" =~ ^[Nn]$ ]]; then
        # Skip SSL installation entirely
        echo -e "\033[1;33m- Skipping SSL certificate installation as per user request.\033[0m\n"  # Yellow
    fi

    if [[ "$CERTBOT_INSTALL" =~ ^[Yy]$ ]]; then
        # Check if ADD_WWW is set or prompt the user
        if [[ -z "$ADD_WWW" ]]; then
            read -p "Do you want to add both ${DOMAIN_NAME} and www.${DOMAIN_NAME} to the SSL certificate? (Y/n): " ADD_WWW
            ADD_WWW=${ADD_WWW:-y}
        fi

        if [[ "$ADD_WWW" =~ ^[Yy]$ ]]; then
            sudo certbot --apache -d ${DOMAIN_NAME} -d www.${DOMAIN_NAME} --non-interactive --agree-tos -m ${EMAIL_ADDRESS} --redirect
        else
            sudo certbot --apache -d ${DOMAIN_NAME} --non-interactive --agree-tos -m ${EMAIL_ADDRESS} --redirect
        fi
    fi
fi

# Instructions if SSL setup fails
echo -e "\033[1;33m- If the SSL setup fails, you can manually attempt to obtain the SSL certificate by running the following command:\033[0m\n"  # Yellow
echo "\033[1;34m- sudo certbot --apache\033[0m\n"

# Final output
echo -e "\033[1;32m- WordPress installation complete. Please complete the setup via your web browser by navigating to http://${DOMAIN_NAME}\033[0m\n"  # Green
