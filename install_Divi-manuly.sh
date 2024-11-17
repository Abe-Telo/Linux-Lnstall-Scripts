#!/bin/bash

# List of plugins and themes to install
declare -A ITEMS
ITEMS["Divi Theme"]="Divi.zip"
ITEMS["Divi Builder Plugin"]="divi-builder.zip"
ITEMS["Extra Magazine Theme"]="Extra.zip"
ITEMS["Bloom Email Opt-in Plugin"]="bloom.zip"
ITEMS["Monarch Social Share Plugin"]="monarch.zip"

# Check for existing and missing zip files
MISSING_ITEMS=()
EXISTING_ITEMS=()
for ITEM_NAME in "${!ITEMS[@]}"; do
    ITEM_FILE="${ITEMS[$ITEM_NAME]}"
    if [ -f "./$ITEM_FILE" ]; then
        EXISTING_ITEMS+=("$ITEM_NAME ($ITEM_FILE)")
    else
        MISSING_ITEMS+=("$ITEM_NAME ($ITEM_FILE)")
    fi
done

# Categorize additional zip files
DIVI_LIBRARY_ITEMS=()
PLUGIN_ITEMS=()
THEME_ITEMS=()
for ZIP_FILE in ./*.zip; do
    [[ -f "$ZIP_FILE" ]] || continue
    ITEM_NAME=$(basename "$ZIP_FILE" .zip)
    if [[ ! " ${ITEMS[@]} " =~ " $ITEM_NAME " ]]; then
        if unzip -l "$ZIP_FILE" | grep -q "\.json" && ! unzip -l "$ZIP_FILE" | grep -q "\.php"; then
            DIVI_LIBRARY_ITEMS+=("$ITEM_NAME ($ZIP_FILE)")
        elif unzip -l "$ZIP_FILE" | grep -q "theme-(header|footer|after|before|wrappers)\.php" || unzip -l "$ZIP_FILE" | grep -q "theme\.json"; then
            THEME_ITEMS+=("$ITEM_NAME ($ZIP_FILE)")
        elif unzip -l "$ZIP_FILE" | grep -q "css/style\.css" && unzip -l "$ZIP_FILE" | grep -q "\.php"; then
            PLUGIN_ITEMS+=("$ITEM_NAME ($ZIP_FILE)")
        else
            PLUGIN_ITEMS+=("$ITEM_NAME ($ZIP_FILE)")
        fi
    fi
done

# Show existing, missing, and categorized zip files
echo -e "\033[1;32mExisting Divi zip files:\033[0m"
for ITEM in "${EXISTING_ITEMS[@]}"; do
    if [[ "$ITEM" == *"Divi Theme"* || "$ITEM" == *"Extra Magazine Theme"* ]]; then
        echo -e "\033[1;34m- $ITEM\033[0m"  # Theme: Blue
    elif [[ "$ITEM" == *"Divi Builder Plugin"* || "$ITEM" == *"Bloom Email Opt-in Plugin"* || "$ITEM" == *"Monarch Social Share Plugin"* ]]; then
        echo -e "\033[1;32m- $ITEM\033[0m"  # Plugin: Green
    fi
done
echo

if [ "${#DIVI_LIBRARY_ITEMS[@]}" -gt 0 ]; then
    echo -e "\033[1;33mDivi Library zip files:\033[0m"
    for ITEM in "${DIVI_LIBRARY_ITEMS[@]}"; do
        echo -e "\033[1;33m- $ITEM\033[0m"
    done
fi
echo

if [ "${#PLUGIN_ITEMS[@]}" -gt 0 ]; then
    echo -e "\033[1;32mAdditional Plugin zip files:\033[0m"
    for ITEM in "${PLUGIN_ITEMS[@]}"; do
        echo -e "\033[1;32m- $ITEM\033[0m"
    done
fi

if [ "${#THEME_ITEMS[@]}" -gt 0 ]; then
    echo -e "\033[1;34mAdditional Theme zip files:\033[0m"
    for ITEM in "${THEME_ITEMS[@]}"; do
        echo -e "\033[1;34m- $ITEM\033[0m"
    done
fi

echo ""

echo -e "\033[1;31mMissing Divi zip files:\033[0m"
for ITEM in "${MISSING_ITEMS[@]}"; do
    echo -e "\033[1;31m- $ITEM\033[0m"
done

echo ""

echo "Please download the missing files from https://www.elegantthemes.com/members-area/download and place them in the same directory as this script."


# Ask for domain name at the beginning
read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME

# Define plugins and themes directory
WP_CONTENT_DIR="/var/www/${DOMAIN_NAME}/wp-content"
WP_PLUGIN_DIR="$WP_CONTENT_DIR/plugins"
WP_THEME_DIR="$WP_CONTENT_DIR/themes"

# Initialize log
LOG_FILE="/tmp/install_log.txt"
echo "Installation Log" > "$LOG_FILE"
echo "================" >> "$LOG_FILE"

# Ensure WordPress directory exists
if [ ! -d "$WP_CONTENT_DIR" ]; then
    echo "Error: WordPress installation not found for ${DOMAIN_NAME}. Please install WordPress first."
    exit 1
fi

# Create plugins and themes directories if they don't exist
mkdir -p "$WP_PLUGIN_DIR" "$WP_THEME_DIR"

# Install each plugin and theme from local files
for ITEM_NAME in "${!ITEMS[@]}"; do
    ITEM_FILE="${ITEMS[$ITEM_NAME]}"

    if [ ! -f "./$ITEM_FILE" ]; then
        echo "Skipping $ITEM_NAME as the zip file is missing."
        echo "$ITEM_NAME - Skipped: File not found" >> "$LOG_FILE"
        continue
    fi

    echo "Using local file for $ITEM_NAME."
    cp "./$ITEM_FILE" "/tmp/${ITEM_NAME}.zip"

    if [[ "$ITEM_NAME" == *"Theme"* ]]; then
        DEST_DIR="$WP_THEME_DIR"
    else
        DEST_DIR="$WP_PLUGIN_DIR"
    fi

    # Check if plugin or theme already exists
    if [ -d "$DEST_DIR/$(basename "$ITEM_FILE" .zip)" ]; then
        read -p "$ITEM_NAME already exists. Do you want to replace it? (y/N): " REPLACE_ITEM
        REPLACE_ITEM=${REPLACE_ITEM:-n}
        if [[ ! "$REPLACE_ITEM" =~ ^[Yy]$ ]]; then
			echo -e "\033[1;31m- Skipping $ITEM_NAME as per user request.\033[0m"
			echo -e "$ITEM_NAME \033[1;31m- Skipped by user\033[0m" >> "$LOG_FILE"
            continue
        fi
        echo "Replacing the existing $ITEM_NAME..."
        rm -rf "$DEST_DIR/$(basename "$ITEM_FILE" .zip)"
    fi

    echo "Unzipping $ITEM_NAME to $DEST_DIR..."
    unzip -o "/tmp/${ITEM_NAME}.zip" -d "$DEST_DIR"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to unzip $ITEM_NAME."
        echo "$ITEM_NAME - Failed: Unzip error" >> "$LOG_FILE"
        continue
    fi

    echo "$ITEM_NAME installed successfully."
    echo "$ITEM_NAME - Installed successfully" >> "$LOG_FILE"

    # Clean up
    rm -f "/tmp/${ITEM_NAME}.zip"
done

# Process any additional zip files in the current directory
for ZIP_FILE in ./*.zip; do
    [[ -f "$ZIP_FILE" ]] || continue
    ITEM_NAME=$(basename "$ZIP_FILE" .zip)

    # Skip if it's already in the predefined items
    if [[ " ${ITEMS[@]} " =~ " $ITEM_NAME " ]]; then
        continue
    fi

    echo "Processing additional file: $ZIP_FILE"
    cp "$ZIP_FILE" "/tmp/${ITEM_NAME}.zip"

    # Determine if it's a theme, plugin, or a Divi Library import
    if unzip -l "/tmp/${ITEM_NAME}.zip" | grep -q "\.json" && ! unzip -l "/tmp/${ITEM_NAME}.zip" | grep -q "\.php"; then
        echo -e "\033[1;33m$ITEM_NAME contains JSON files and is likely a Divi Library layout.\033[0m"
        echo -e "\033[1;33mPlease manually import $ITEM_NAME into the Divi Library through the WordPress admin panel.\033[0m"
        echo -e  "$ITEM_NAME \033[1;33m-  Requires manual import\033[0m" >> "$LOG_FILE"
        rm -f "/tmp/${ITEM_NAME}.zip"
        continue
    fi

    if unzip -l "/tmp/${ITEM_NAME}.zip" | grep -q "theme-(header|footer|after|before|wrappers)\.php" || unzip -l "/tmp/${ITEM_NAME}.zip" | grep -q "theme\.json"; then
        DEST_DIR="$WP_THEME_DIR"
        echo "$ITEM_NAME identified as a theme."
    elif unzip -l "/tmp/${ITEM_NAME}.zip" | grep -q "css/style\.css" && unzip -l "/tmp/${ITEM_NAME}.zip" | grep -q "\.php"; then
        DEST_DIR="$WP_PLUGIN_DIR"
        echo "$ITEM_NAME identified as a plugin."
    else
        DEST_DIR="$WP_PLUGIN_DIR"
        echo "$ITEM_NAME identified as a plugin."
    fi

    # Check if plugin or theme already exists
    if [ -d "$DEST_DIR/$ITEM_NAME" ]; then
        read -p "$ITEM_NAME already exists. Do you want to replace it? (y/N): " REPLACE_ITEM
        REPLACE_ITEM=${REPLACE_ITEM:-n}
        if [[ ! "$REPLACE_ITEM" =~ ^[Yy]$ ]]; then 
			echo -e "\033[1;31m- Skipping $ITEM_NAME as per user request.\033[0m"
			echo -e "$ITEM_NAME \033[1;31m- Skipped by user\033[0m" >> "$LOG_FILE"
            continue
        fi
        echo "Replacing the existing $ITEM_NAME..."
        rm -rf "$DEST_DIR/$ITEM_NAME"
    fi

    echo "Unzipping $ITEM_NAME to $DEST_DIR..."
    unzip -o "/tmp/${ITEM_NAME}.zip" -d "$DEST_DIR"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to unzip $ITEM_NAME."
        echo "$ITEM_NAME - Failed: Unzip error" >> "$LOG_FILE"
        continue
    fi

    echo "$ITEM_NAME installed successfully."
    echo "$ITEM_NAME - Installed successfully" >> "$LOG_FILE"

    # Clean up
    rm -f "/tmp/${ITEM_NAME}.zip"
done

# Set permissions
sudo chown -R www-data:www-data "$WP_CONTENT_DIR"
sudo chmod -R 755 "$WP_CONTENT_DIR"

# Final output
echo "Plugins and themes installation complete."
echo "Check the log file at \$LOG_FILE for details."
cat "$LOG_FILE"
