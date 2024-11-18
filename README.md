# Linux-Lnstall-Scripts

To install WordPress, use this one-liner:

V1.0 Stable Straight Forword wordpress install 
```bash
curl -sLO https://raw.githubusercontent.com/Abe-Telo/Linux-Lnstall-Scripts/main/install_wordpress.sh && chmod +x install_wordpress.sh && sudo ./install_wordpress.sh
```
V2.0 Beta With Advance Help and custom install filters.
```bash
curl -sLO https://raw.githubusercontent.com/Abe-Telo/Linux-Lnstall-Scripts/main/install_wordpress.sh && chmod +x install_wordpress.sh && sudo ./install_wordpress.sh
```
For Usage in 2.0 Beta
```
sudo ./install_wordpress.sh -h
```

This command will download and execute the script automatically, setting up WordPress with the necessary components for a tested on Debian 12. It is expected to work on other environments, including Debian and Ubuntu, but please test and confirm compatibility..

## What It Does

This script automates the installation and configuration of WordPress on a Debian 12 server (tested). It may also work on other environments, including Debian and Ubuntu.. It performs the following actions:

1. **Updates and Upgrades System Packages**: Ensures all system packages are up to date.
2. **Installs Required Software**:
   - Apache web server
   - MariaDB database server
   - PHP 8.2 and required extensions (e.g., `php8.2-cli`, `php8.2-curl`, `php8.2-zip`)
   - `wget`, `unzip` for downloading and extracting WordPress
3. **Secures MariaDB Installation**: Sets a secure root password and removes unnecessary defaults.
4. **Creates Database and User for WordPress**: Generates a database, user, and secure password for WordPress.
5. **Downloads and Sets Up WordPress**: Downloads the latest version of WordPress, configures it, and sets appropriate file permissions.
6. **Configures Apache Virtual Host**: Sets up an Apache virtual host to serve the WordPress site.
7. **Configures SSL with Certbot**: Installs Certbot using Snap and sets up SSL for the domain.
8. **Creates a Backup of worpress files:** Currently we only backup Wordpress files. (To implement DB Backups.)

## Installed Components

- **Apache**: The web server used to serve your WordPress site.
- **MariaDB**: The database server used to store your WordPress data.
- **PHP 8.2**: The scripting language required for WordPress, along with several necessary extensions.
- **Certbot**: Used for setting up and renewing SSL certificates automatically.

