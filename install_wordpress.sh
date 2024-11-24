#!/bin/bash

#set -x  # Enable script debugging

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo -e "\033[1;31mPlease run as root. Exiting.\033[0m\n"  # Red
  exit 1
fi

# Global Directory
BACKUP_TIMESTAMP=$(date +%Y%m%d%H%M%S)
UNIQUE_ID=$(command -v uuidgen >/dev/null 2>&1 && uuidgen || echo $RANDOM)
BACKUP_DIR="/var/backups/${DOMAIN_NAME}_${BACKUP_TIMESTAMP}_${UNIQUE_ID}.tar.gz"
BACKUP_FILES=(/var/backups/${DOMAIN_NAME}_*.tar.gz)
DB_LOG_FILE="/root/db_log.txt"
# Log file for tracking actions
LOG_FILE="/var/log/wp_setup.log"
DOMAIN_PATH="/var/www" #/var/www/${DOMAIN_NAME}



# Log output to both terminal and log file
exec 2>&1 | tee -a "$LOG_FILE"
#@exec > >(tee -a <(while IFS= read -r line; do echo "$(date): $line"; done >> "$LOG_FILE")) 2>&1 
#exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE.err" >&2)
#exec > >(tee -a "$LOG_FILE") 2>&1

command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but it's not installed. Exiting."; exit 1; }




show_help() {
    PUBLIC_IP=$(curl -s -4 ifconfig.me)

    echo -e "\033[1;33mPlease make sure you're pointing your DNS A Records to your server's IP address. \033[0m"
    echo -e "\033[1;33mAlternatively, use http://$PUBLIC_IP (Note: Certbot will not work if the A record is not pointed correctly).\033[0m"
    
    echo 
    echo "Usage: $0 [-b] [-r] [-d] [-s] [-x] [-u] [-z] [--certbot Y/N] [--domain example.com] [--skip-system-update] [--skip-package-install] [--skip-secure-mysql] [--skip-db-creation]"
    echo ""
    echo "How to install:"
    echo "   -install                    Will install the regular method"
    echo "   -install certbot or call function            "
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
	echo "Start"
	echo -e "All script season data will be stored in  ${DB_LOG_FILE} and will be reused."
	echo -e "All log files for debugging will be stored in ${LOG_FILE}"
	echo -e "All backup files will be stored ${BACKUP_FILES}"
	echo -e "Current DB_KEY name is DB_KEY || empty "
	
}

#CERTBOT_INSTALL="Y"  # Default to Yes for SSL installation



 
# Function to ask for domain name if not provided and validate it
ask_for_domain_name() {
    # Check if the domain name is already set
    if [ -z "$DOMAIN_NAME" ]; then
        # Check if there is a previously used domain and prompt user
        if [ -f "$DB_LOG_FILE" ] && DOMAIN_NAME=$(awk -F'=' '/last_domain_used/ {print $2}' "$DB_LOG_FILE"); then
            while true; do
                read -p "Last domain used was ${DOMAIN_NAME}. Do you want to use it? (y/n): " use_last_domain
                case "${use_last_domain:-~ ^[Yy]$}" in
                    [Yy]*) break ;;
                    [Nn]*) DOMAIN_NAME=""; break ;;
                    *) echo -e "\033[1;31mInvalid input. Please enter 'Y' or 'N'.\033[0m" ;;
					
                esac 
            done
        fi
        # Prompt for a new domain if the previous one is not used
        if [ -z "$DOMAIN_NAME" ]; then
            while true; do
                read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
                [[ "$DOMAIN_NAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]] && break
                echo -e "\033[1;31mInvalid domain name. Please enter a valid domain name.\033[0m"
            done

            # Save the new domain for future use
            echo "last_domain_used=${DOMAIN_NAME}" > "$DB_LOG_FILE"
        fi
    fi
}



# Function to update and upgrade the system
update_system() {
    echo -e "\033[1;34mChecking if the system is already up-to-date...\033[0m"  # Blue

    # Check if there are available updates
    AVAILABLE_UPDATES=$(apt-get -s upgrade | grep "upgraded," | awk '{print $1}')
    
    if [ "$AVAILABLE_UPDATES" -eq 0 ]; then
        echo -e "\033[1;32mSystem is already up-to-date. Skipping update.\033[0m"  # Green
    else
        echo -e "\033[1;34mUpdates are available. Proceeding with system update...\033[0m"  # Blue
        sudo apt-get update && sudo apt-get upgrade -y || { echo -e "\033[1;31mSystem update/upgrade failed. Exiting.\033[0m\n"; exit 1; }
    fi
}

# Function to install required packages
install_packages() {
    PACKAGES=(apache2 mariadb-server php8.2 php8.2-cli php8.2-common php8.2-imap php8.2-redis php8.2-snmp php8.2-xml php8.2-mysql php8.2-zip php8.2-mbstring php8.2-curl libapache2-mod-php wget unzip expect)
    MISSING_PACKAGES=()
    UPDATE_PACKAGES=()

    for PACKAGE in "${PACKAGES[@]}"; do
        if ! dpkg -s "$PACKAGE" >/dev/null 2>&1; then
            MISSING_PACKAGES+=("$PACKAGE")
        elif apt list --upgradable 2>/dev/null | grep -q "^$PACKAGE/"; then
            UPDATE_PACKAGES+=("$PACKAGE")
        fi
    done

    if [ "${#MISSING_PACKAGES[@]}" -ne 0 ]; then
        echo -e "\033[1;34mInstalling missing packages: ${MISSING_PACKAGES[*]}\033[0m"  # Blue
        sudo apt-get install -y "${MISSING_PACKAGES[@]}" || { echo -e "\033[1;31mFailed to install required packages. Exiting.\033[0m\n"; exit 1; }
    fi

    if [ "${#UPDATE_PACKAGES[@]}" -ne 0 ]; then
        echo -e "\033[1;34mThe following packages can be updated: ${UPDATE_PACKAGES[*]}\033[0m"  # Blue
        read -p "Do you want to update these packages? (Y/n): " UPDATE_CONFIRM
        UPDATE_CONFIRM=${UPDATE_CONFIRM:-Y}
        if [[ "$UPDATE_CONFIRM" =~ ^[Yy]$ ]]; then
            sudo apt-get upgrade -y "${UPDATE_PACKAGES[@]}" || { echo -e "\033[1;31mFailed to update packages. Exiting.\033[0m\n"; exit 1; }
        else
            echo -e "\033[1;33mPackage update skipped by user request.\033[0m"  # Yellow
        fi
    fi
}


# Function to secure MariaDB installation
secure_mysql() {
    if [ "$SKIP_SECURE_MYSQL" != "true" ]; then
        ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=')
        ROOT_PASSWORD_EXISTS=$(sudo mysql -u root -e "SELECT 1 FROM mysql.user WHERE user='root' AND authentication_string != '';" 2>/dev/null | grep 1)

        if [ -z "$ROOT_PASSWORD_EXISTS" ]; then
            echo -e "\033[1;34mSecuring MariaDB installation. Please wait...\033[0m"  # Blue
            echo "Securing MariaDB: Running mysql_secure_installation." >> "$LOG_FILE"
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

            # Verify if the password was successfully set
            ROOT_PASSWORD_EXISTS=$(sudo mysql -u root -e "SELECT 1 FROM mysql.user WHERE user='root' AND authentication_string != '';" 2>/dev/null | grep 1)
            if [ -n "$ROOT_PASSWORD_EXISTS" ]; then
                echo -e "\033[1;32mMariaDB installation secured successfully.\033[0m"  # Green
                echo "Securing MariaDB: Successfully completed." >> "$LOG_FILE"
            else
                echo -e "\033[1;31mFailed to secure MariaDB installation.\033[0m"  # Red
                echo "Securing MariaDB: Failed." >> "$LOG_FILE"
            fi
        else
            echo -e "\033[1;33mMariaDB root password is already set. Skipping secure installation.\033[0m"  # Yellow
            echo "Securing MariaDB: Skipped as root password is already set." >> "$LOG_FILE"
        fi
    else
        echo -e "\033[1;33mSkipping MariaDB secure installation as per user request.\033[0m"  # Yellow
        echo "Securing MariaDB: Skipped by user request." >> "$LOG_FILE"
    fi
}

# Function to create and validate database credentials if they do not exist


 
# Function to get credentials from wp-config.php
get_credentials_from_wpconfig() {
    WP_CONFIG_PATH="${DOMAIN_PATH}/${DOMAIN_NAME}/wp-config.php"
	echo -e "\033[1;32m- WORDPRESS WP-Config.php HAS THE FOLLOWING IN > ${WP_CONFIG_PATH}\033[0m"
		# Extract credentials from wp-config.php
		WP_DB_NAME=$(grep "DB_NAME" "${WP_CONFIG_PATH}" | sed -n "s/.*'DB_NAME', '\([^']*\)'.*/\1/p")
		WP_DB_USER=$(grep "DB_USER" "${WP_CONFIG_PATH}" | sed -n "s/.*'DB_USER', '\([^']*\)'.*/\1/p")
		WP_DB_PASSWORD=$(grep "DB_PASSWORD" "${WP_CONFIG_PATH}" | sed -n "s/.*'DB_PASSWORD', '\([^']*\)'.*/\1/p")
    
    # Display only the extracted credentials
	echo -e "WP_DB_NAME=${WP_DB_NAME}\nWP_DB_USER=${WP_DB_USER}\nWP_DB_PASSWORD=${WP_DB_PASSWORD}\n"
}
	
 
# Function to retrieve credentials from the log file
get_credentials_from_log() {
	echo -e "\033[1;32m- WORDPRESS SETUP DATA FILE HAS THE FOLLOWING IN > ${DB_LOG_FILE}\033[0m"
		DB_NAME=$(grep "${DB_KEY}_DB_NAME" "${DB_LOG_FILE}" | cut -d '=' -f2)
		DB_USER=$(grep "${DB_KEY}_DB_USER" "${DB_LOG_FILE}" | cut -d '=' -f2)
		DB_PASSWORD=$(grep "${DB_KEY}_DB_PASSWORD" "${DB_LOG_FILE}" | cut -d '=' -f2)
		echo -e "DB_NAME=${DB_NAME}\nDB_USER=${DB_USER}\nDB_PASSWORD=${DB_PASSWORD}\n"
}

# Function to generate new credentials and append to log file
generate_new_credentials() {
    DB_NAME="${DB_KEY}_db_$(openssl rand -hex 4)"
    DB_USER="${DB_KEY}_user_$(openssl rand -hex 4)"
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=')
    {
        echo "${DB_KEY}_DB_NAME=${DB_NAME}"
        echo "${DB_KEY}_DB_USER=${DB_USER}"
        echo "${DB_KEY}_DB_PASSWORD=${DB_PASSWORD}"
    } >> ${DB_LOG_FILE}
}


# Function to create the database and user in MariaDB
create_database_and_user() {
    sudo mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    echo -e "\033[1;32mDatabase and user created successfully.\033[0m\n"
}

# Main function to check and create database credentials if they do not exist
check_and_create_db_credentials() {
    DB_KEY="$(echo ${DOMAIN_NAME} | tr '.' '_')"
    WP_CONFIG_PATH="${DOMAIN_PATH}/${DOMAIN_NAME}/wp-config.php"

    # Check if DB_LOG_FILE exists and contains the database key
    if [ -f "${DB_LOG_FILE}" ] && grep -q "${DB_KEY}_DB_NAME" "${DB_LOG_FILE}"; then
        echo -e "\033[1;32m- Using existing database credentials from log file.\033[0m\n"
        get_credentials_from_log
    else
        echo -e "\033[1;33m- No existing credentials found. Generating new credentials.\033[0m\n"
        generate_new_credentials
    fi

    # Check if wp-config.php exists
    if [ -f "${WP_CONFIG_PATH}" ]; then
        update_wp_config
    else
        echo -e "\033[1;33m- wp-config.php not found. Proceeding with database creation for new installation.\033[0m\n"
        echo -e "\033[1;33m- WordPress Site not found. Proceeding with database creation for new installation.\033[0m\n" 
		#wordpress_installation_logic
    fi

    # Create the database and user in MySQL
    create_database_and_user
}
 
# Function to view database information
view_db_info() {
    cat /root/db_log.txt /root/email_log.txt
}

# Function to delete database information
delete_db_info() {
    rm -f ${DB_LOG_FILE} /root/email_log.txt
    echo -e "\033[1;32mDatabase and email information deleted successfully.\033[0m"
}

# Function to update wp-config.php with database credentials
update_wp_config() {
    WP_CONFIG_PATH="${DOMAIN_PATH}/${DOMAIN_NAME}/wp-config.php" 
    if grep -q "${DB_KEY}_DB_NAME" ${DB_LOG_FILE}; then
        DB_NAME_LOG=$(grep "${DB_KEY}_DB_NAME" ${DB_LOG_FILE} | cut -d '=' -f2)
        DB_USER_LOG=$(grep "${DB_KEY}_DB_USER" ${DB_LOG_FILE} | cut -d '=' -f2)
        DB_PASSWORD_LOG=$(grep "${DB_KEY}_DB_PASSWORD" ${DB_LOG_FILE} | cut -d '=' -f2)

        # Check if wp-config.php has default values or no values
        if grep -qE "define\( 'DB_NAME', 'database_name_here' \)|define\( 'DB_NAME', '' \)" ${WP_CONFIG_PATH} && \
           grep -qE "define\( 'DB_USER', 'username_here' \)|define\( 'DB_USER', '' \)" ${WP_CONFIG_PATH} && \
           grep -qE "define\( 'DB_PASSWORD', 'password_here' \)|define\( 'DB_PASSWORD', '' \)" ${WP_CONFIG_PATH}; then
            echo -e "\033[1;33mFound Default or No Values in wp-config.php.\033[0m"  # Yellow
            echo -e "\033[1;34mProceed to add DB info to wp-config.php as there are default or empty values.\033[0m"  # Blue
            # Add the new DB info to wp-config.php
            DB_NAME_ESCAPED=$(printf '%s' "$DB_NAME_LOG" | sed -e 's/[\/&]/\\&/g')
            DB_USER_ESCAPED=$(printf '%s' "$DB_USER_LOG" | sed -e 's/[\/&]/\\&/g')
            DB_PASSWORD_ESCAPED=$(printf '%s' "$DB_PASSWORD_LOG" | sed -e 's/[\/&]/\\&/g')
            sudo sed -i "s/define( 'DB_NAME', 'database_name_here' )/define( 'DB_NAME', '${DB_NAME_ESCAPED}' )/" ${WP_CONFIG_PATH} || { echo "Error: Failed to set DB_NAME in ${WP_CONFIG_PATH}"; exit 1; }
            sudo sed -i "s/define( 'DB_USER', 'username_here' )/define( 'DB_USER', '${DB_USER_ESCAPED}' )/" ${WP_CONFIG_PATH} || { echo "Error: Failed to set DB_USER in ${WP_CONFIG_PATH}"; exit 1; }
            sudo sed -i "s/define( 'DB_PASSWORD', 'password_here' )/define( 'DB_PASSWORD', '${DB_PASSWORD_ESCAPED}' )/" ${WP_CONFIG_PATH} || { echo "Error: Failed to set DB_PASSWORD in ${WP_CONFIG_PATH}"; exit 1; }
        elif grep -q "define( 'DB_NAME', '${DB_NAME_LOG}'" ${WP_CONFIG_PATH} && \
             grep -q "define( 'DB_USER', '${DB_USER_LOG}'" ${WP_CONFIG_PATH} && \
             grep -q "define( 'DB_PASSWORD', '${DB_PASSWORD_LOG}'" ${WP_CONFIG_PATH}; then
            echo -e "\033[1;32mDatabase credentials already exist in wp-config.php and match the log file.\033[0m"  # Green
        else
            echo -e "\033[1;31mConflict detected between wp-config.php and db_log.txt.\033[0m"  # Red
            #echo "Current wp-config.php values:"
			
  
            #grep "define( 'DB_NAME'" ${WP_CONFIG_PATH}
            #grep "define( 'DB_USER'" ${WP_CONFIG_PATH}
            #grep "define( 'DB_PASSWORD'" ${WP_CONFIG_PATH}
            #echo -e "Log file values:"
            #echo -e "DB_NAME=${DB_NAME_LOG}"
            #echo "DB_USER=${DB_USER_LOG}"
            #echo "DB_PASSWORD=${DB_PASSWORD_LOG}"
			#get_credentials_from_log
			get_credentials_from_wpconfig
            read -p "Keep the values in wp-config.php or replace with log file values? (Keep/Replace, default is Keep): " REPLACE_VALUES
            REPLACE_VALUES=${REPLACE_VALUES:-Keep}
            if [[ "$REPLACE_VALUES" =~ ^[Rr]eplace$ ]]; then
                DB_NAME_ESCAPED=$(printf '%s' "$DB_NAME_LOG" | sed -e 's/[\/&]/\\&/g')
                DB_USER_ESCAPED=$(printf '%s' "$DB_USER_LOG" | sed -e 's/[\/&]/\\&/g')
                DB_PASSWORD_ESCAPED=$(printf '%s' "$DB_PASSWORD_LOG" | sed -e 's/[\/&]/\\&/g')
                sudo sed -i "s/define( 'DB_NAME', .*)/define( 'DB_NAME', '${DB_NAME_ESCAPED}' )/" ${WP_CONFIG_PATH}
                sudo sed -i "s/define( 'DB_USER', .*)/define( 'DB_USER', '${DB_USER_ESCAPED}' )/" ${WP_CONFIG_PATH}
                sudo sed -i "s/define( 'DB_PASSWORD', .*)/define( 'DB_PASSWORD', '${DB_PASSWORD_ESCAPED}' )/" ${WP_CONFIG_PATH}
            else
                echo -e "\033[1;32mKeeping existing values in wp-config.php.\033[0m"  # Green
            fi
        fi
    else
        # If there are no existing entries, add them
        if ! grep -q "define( 'DB_NAME', '${DB_NAME}'" ${WP_CONFIG_PATH}; then
            DB_NAME_ESCAPED=$(printf '%s' "$DB_NAME" | sed -e 's/[\/&]/\\&/g')
            sudo sed -i "s/define( 'DB_NAME', 'database_name_here' )/define( 'DB_NAME', '${DB_NAME_ESCAPED}' )/" ${WP_CONFIG_PATH} || { echo "Error: Failed to set DB_NAME in wp-config.php"; exit 1; }
        fi
        if ! grep -q "define( 'DB_USER', '${DB_USER}'" ${WP_CONFIG_PATH}; then
            DB_USER_ESCAPED=$(printf '%s' "$DB_USER" | sed -e 's/[\/&]/\\&/g')
            sudo sed -i "s/define( 'DB_USER', 'username_here' )/define( 'DB_USER', '${DB_USER_ESCAPED}' )/" ${WP_CONFIG_PATH} || { echo "Error: Failed to set DB_USER in wp-config.php"; exit 1; }
        fi
        if ! grep -q "define( 'DB_PASSWORD', '${DB_PASSWORD}'" ${WP_CONFIG_PATH}; then
            DB_PASSWORD_ESCAPED=$(printf '%s' "$DB_PASSWORD" | sed -e 's/[\/&]/\\&/g')
            sudo sed -i "s/define( 'DB_PASSWORD', 'password_here' )/define( 'DB_PASSWORD', '${DB_PASSWORD_ESCAPED}' )/" ${WP_CONFIG_PATH} || { echo "Error: Failed to set DB_PASSWORD in wp-config.php"; exit 1; }
        fi
    fi
}

# Function to start and enable services
start_services() {
    sudo systemctl start apache2 || { echo -e "\033[1;31mFailed to start Apache. Exiting.\033[0m\n"; exit 1; }
    sudo systemctl enable apache2 || { echo -e "\033[1;31mFailed to enable Apache. Exiting.\033[0m\n"; exit 1; }
    sudo systemctl start mariadb || { echo -e "\033[1;31mFailed to start MariaDB. Exiting.\033[0m\n"; exit 1; }
    sudo systemctl enable mariadb || { echo -e "\033[1;31mFailed to enable MariaDB. Exiting.\033[0m\n"; exit 1; }
}

# Function to prompt the user for backup actions
prompt_backup_action() {
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
			perform_backup_action
        else
            echo -e "\033[1;33mNo existing backups found. Proceeding with new backup creation.\033[0m\n"  # Yellow
            BACKUP_ACTION="b"
			perform_backup_action
        fi
    fi

    # Validate user input
    if ! [[ "$BACKUP_ACTION" =~ ^(b|r|d|s|u|x|z)$ ]]; then
        echo -e "\033[1;31mInvalid option. Exiting.\033[0m\n"  # Red
        exit 1
    fi
}

# Function to create a new backup
create_backup() { 
    echo -e "\033[1;34mCreating backup of existing WordPress installation at ${BACKUP_DIR}\033[0m\n"  # Blue
    if [ -d "${DOMAIN_PATH}/${DOMAIN_NAME}" ]; then
        tar -czf "${BACKUP_DIR}" -C "${DOMAIN_PATH}" "${DOMAIN_NAME}" --checkpoint=.100 || { echo -e "\033[1;31mFailed to create backup. Exiting.\033[0m\n"; exit 1; }
        echo -e "\033[1;32mBackup created successfully.\033[0m\n"  # Green
    else
        echo -e "\033[1;31mDirectory ${DOMAIN_PATH}/${DOMAIN_NAME} does not exist. Skipping backup.\033[0m\n"  # Red
    fi
}

# Function to perform backup action
perform_backup_action() {
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
                    sudo mkdir -p "$UNZIP_DIR" && sudo tar -xzf "${BACKUP_FILES[$i]}" -C "$UNZIP_DIR" --checkpoint=.100 || { echo -e "\033[1;31mFailed to unzip backup ${BACKUP_FILES[$i]}.\033[0m\n"; }
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
                    sudo tar -xzf "${BACKUP_FILES[$i]}" -C "${DOMAIN_PATH}" --checkpoint=.100 || { echo -e "\033[1;31mFailed to restore backup ${BACKUP_FILES[$i]}.\033[0m\n"; exit 1; }
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
}

# Download WordPress if latest.tar.gz is missing or corrupted
#cd /tmp
#sudo apt-get install unzip -y || { echo -e "\033[1;31mFailed to install unzip. Exiting.\033[0m\n"; exit 1; }
#echo -e "\033[1;33mJust unzip latest.zip?\033[0m\n"  # Yellow

# Function to handle WordPress installation logic
wordpress_installation_logic() {
echo -e "Whatever"
echo -e "${DOMAIN_PATH}/${DOMAIN_NAME}"
    if [ -d "${DOMAIN_PATH}/${DOMAIN_NAME}" ]; then
        read -p "Already found WordPress site installed for ${DOMAIN_NAME}. Do you want to replace it? (y/N): " REPLACE_WORDPRESS
        REPLACE_WORDPRESS=${REPLACE_WORDPRESS,,}  # Convert to lowercase
        REPLACE_WORDPRESS=${REPLACE_WORDPRESS:-n}
        if [[ "$REPLACE_WORDPRESS" =~ ^[y]$ ]]; then
            echo -e "\033[1;33mReplacing the existing WordPress installation...\033[0m\n"  # Yellow
            #echo -e "\033[1;33mBacking up old wordpress site...\033[0m\n"  # Yellow
            #echo -e "\033[1;33mRemoving Old site Directory...\033[0m\n"  # Yellow 
            sudo rm -rf ${DOMAIN_PATH}/${DOMAIN_NAME} || { echo -e "\033[1;31mFailed to remove existing WordPress directory. Exiting.\033[0m\n"; exit 1; }
			download_wordpress
			extract_wordpress
			rename_wp_config_sample
			set_permissions 
			configure_wp_config
			add_cleanup_trap
        else
            echo -e "\033[1;33mSkipping WordPress installation as per user request. Continuing with other tasks.\033[0m\n"  # Yellow
        fi
    else
        # Directory does not exist - proceed with WordPress setup for a new domain
        echo -e "\033[1;32mNo existing WordPress directory found. Proceeding with fresh installation...\033[0m\n"
        download_wordpress
        extract_wordpress
        rename_wp_config_sample
        set_permissions
		configure_wp_config
        add_cleanup_trap
    fi
}

# Function to download and validate WordPress
download_wordpress() {
    if [ ! -f "latest.tar.gz" ]; then
        echo -e "\033[1;34mDownloading WordPress package...\033[0m\n"  # Blue
        wget --progress=bar:force https://wordpress.org/latest.tar.gz -O latest.tar.gz || { echo -e "\033[1;31mFailed to download WordPress. Exiting.\033[0m\n"; exit 1; }
    fi 

    # Validate the downloaded tar file to ensure it's not corrupted
    if ! tar -tzf latest.tar.gz > /dev/null 2>&1; then
        echo -e "\033[1;31mThe WordPress archive seems to be corrupted. Exiting.\033[0m\n"  # Red
        exit 1
    fi
}

# Function to extract and install WordPress
extract_wordpress() {
    if [ ! -d "${DOMAIN_PATH}/${DOMAIN_NAME}" ]; then
        echo -e "\033[1;34mExtracting WordPress to /tmp/wordpress_unzip\033[0m\n"  # Blue
        mkdir -p /tmp/wordpress_unzip
        sudo tar -xzf latest.tar.gz -C /tmp/wordpress_unzip --checkpoint=.100 || { echo -e "\033[1;31mFailed to extract WordPress. Exiting.\033[0m\n"; exit 1; }
        sudo rm -rf ${DOMAIN_PATH}/${DOMAIN_NAME}

        # Check if the extraction was successful
        if [ ! -d "/tmp/wordpress_unzip/wordpress" ]; then
            echo -e "\033[1;31mFailed to extract WordPress files properly. Exiting.\033[0m\n"  # Red
            exit 1
        fi

        echo -e "\033[1;34m > DONE. \033[0m\n"  # Blue
        echo -e "\033[1;34m- Rsync WordPress files to ${DOMAIN_PATH}/${DOMAIN_NAME} \033[0m\n"  # Blue

        sudo rsync -ah /tmp/wordpress_unzip/wordpress/ ${DOMAIN_PATH}/${DOMAIN_NAME}/
        sudo rm -rf /tmp/wordpress_unzip
    fi
}

# Function to move wp-config-sample.php to wp-config.php and set database info
rename_wp_config_sample() {
    cd ${DOMAIN_PATH}/${DOMAIN_NAME}
    if [ -f wp-config-sample.php ]; then
        if [ ! -f wp-config.php ]; then
            sudo cp wp-config-sample.php wp-config.php || { echo -e "\033[1;31mFailed to copy wp-config-sample.php to wp-config.php. Exiting.\033[0m\n"; exit 1; }
        fi
    else
        echo -e "\033[1;31mError: wp-config-sample.php not found. Exiting.\033[0m\n"  # Red
        exit 1
    fi
}

# Function to set permissions for WordPress directory
set_permissions() {
    echo -e "\033[1;34mSetting chown and permissions\033[0m\n"  # Blue
    sudo chown -R www-data:www-data ${DOMAIN_PATH}/${DOMAIN_NAME} || { echo -e "\033[1;31mFailed to set ownership for WordPress directory. Exiting.\033[0m\n"; exit 1; }
    sudo chmod -R 750 ${DOMAIN_PATH}/${DOMAIN_NAME} || { echo -e "\033[1;31mFailed to set permissions for WordPress directory. Exiting.\033[0m\n"; exit 1; }
}

# Function to add a cleanup trap to remove temporary directories
add_cleanup_trap() {
    trap "sudo rm -rf /tmp/wordpress_unzip; echo -e '\033[1;34mCleanup complete.\033[0m\n'" EXIT
}


# Function to configure wp-config.php with database credentials
configure_wp_config() {
    if [ -f wp-config.php ]; then
        DB_NAME=$(grep "${DB_KEY}_DB_NAME" ${DB_LOG_FILE} | cut -d '=' -f2)
        DB_USER=$(grep "${DB_KEY}_DB_USER" ${DB_LOG_FILE} | cut -d '=' -f2)
        DB_PASSWORD=$(grep "${DB_KEY}_DB_PASSWORD" ${DB_LOG_FILE} | cut -d '=' -f2)

        if [ -n "$DB_NAME" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ]; then
            sudo sed -i "s/define( 'DB_NAME', *'[^']*' )/define( 'DB_NAME', '${DB_NAME}' )/" wp-config.php
            sudo sed -i "s/define( 'DB_USER', *'[^']*' )/define( 'DB_USER', '${DB_USER}' )/" wp-config.php
            sudo sed -i "s/define( 'DB_PASSWORD', *'[^']*' )/define( 'DB_PASSWORD', '${DB_PASSWORD}' )/" wp-config.php
            echo -e "\033[1;32mUpdated wp-config.php with database credentials.\033[0m\n"  # Green
        else
            echo -e "\033[1;31mDatabase credentials are missing in the log file. Exiting.\033[0m\n"  # Red
            exit 1
        fi
    else
        echo -e "\033[1;31mwp-config.php not found. Exiting.\033[0m\n"  # Red
        exit 1
    fi
}

# Function to configure PHP settings for WordPress
configure_php_settings() {
    PHP_INI_PATH="/etc/php/8.2/apache2/php.ini"
    POST_MAX_SIZE=$(grep -i '^post_max_size' $PHP_INI_PATH | awk -F' = ' '{print $2}' | tr -d 'M')
    UPLOAD_MAX_FILESIZE=$(grep -i '^upload_max_filesize' $PHP_INI_PATH | awk -F' = ' '{print $2}' | tr -d 'M')
    MEMORY_LIMIT=$(grep -i '^memory_limit' $PHP_INI_PATH | awk -F' = ' '{print $2}' | tr -d 'M')

    if [[ "${POST_MAX_SIZE}" -lt 500 ]]; then
        sudo sed -i "s/post_max_size = .*/post_max_size = 500M/" $PHP_INI_PATH || { echo -e "\033[1;31mFailed to set post_max_size. Exiting.\033[0m\n"; exit 1; }
		echo -e "post_max_size=500"
    fi

    if [[ "${UPLOAD_MAX_FILESIZE}" -lt 500 ]]; then
        sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = 500M/" $PHP_INI_PATH || { echo -e "\033[1;31mFailed to set upload_max_filesize. Exiting.\033[0m\n"; exit 1; }
		echo -e "upload_max_filesize=500"
    fi

    if [[ "${MEMORY_LIMIT}" -lt 256 ]]; then
        sudo sed -i "s/memory_limit = .*/memory_limit = 256M/" $PHP_INI_PATH || { echo -e "\033[1;31mFailed to set memory_limit. Exiting.\033[0m\n"; exit 1; }
		echo -e "memory_limit=256"
    fi
}

# Function to create Apache virtual host for WordPress
create_virtual_host() {
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
    DocumentRoot ${DOMAIN_PATH}/${DOMAIN_NAME}

    <Directory ${DOMAIN_PATH}/${DOMAIN_NAME}>
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
}

# Function to install and configure SSL with Certbot
install_certbot() {
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
}


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
                start)
					ask_for_domain_name
					update_system
					install_packages		
					prompt_backup_action
                    wordpress_installation_logic 
					start_services
					secure_mysql
					check_and_create_db_credentials
					configure_php_settings
					create_virtual_host
					install_certbot
					complete
                    ;;
                *)
                    show_help
                    ;;
                createDB)
                    check_and_create_db_credentials
					#add_cleanup_trap()
					#set_permissions()
                    ;;
                wpconfig)
                    CERTBOT_INSTALL="${!OPTIND}"; OPTIND=$((OPTIND + 1)) 
                    ;;
                startservice)
                    start_services
                    ;;
                installWP)
					download_wordpress
                    wordpress_installation_logic
					extract_wordpress
                    ;;
                configure_php_settings)
                    CERTBOT_INSTALL="${!OPTIND}"; OPTIND=$((OPTIND + 1))
                    ;;
                create_virtual_host)
                    CERTBOT_INSTALL="${!OPTIND}"; OPTIND=$((OPTIND + 1))
                    ;;
                certbot)
                    CERTBOT_INSTALL="${!OPTIND}"; OPTIND=$((OPTIND + 1))
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
                    cat ${LOG_FILE}
                    exit 0
                    ;;
                delete-db-info)
                    rm -f /root/db_log.txt /root/email_log.txt
                    echo -e "\033[1;32mDatabase and email information deleted successfully.\033[0m"
                    exit 0
                    ;;
                *)
                    #echo -e "\033[1;31mInvalid option: --$OPTARG\033[0m\n"  # Red
					echo -e " Type --start or -help for supsific options. "
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
 
 # If nothing was entered, show help message
if [ $# -eq 0 ]; then
    echo -e "\033[1;32m-  Type --start or --help for specific options. \033[0m\n"
	echo  "last_domain_used=${DOMAIN_NAME}" 
    exit 1
fi
 
# Final output
complete() {
echo -e "\033[1;32m- WordPress installation complete. Please complete the setup via your web browser by navigating to http://${DOMAIN_NAME}\033[0m\n"  # Green
}

