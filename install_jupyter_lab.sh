#!/bin/bash
# install_jupyter_lab_service.sh
#
# This script installs JupyterLab on Debian 12 within a virtual environment,
# installs Node.js and npm (creating a "node" symlink if needed),
# sets your Jupyter Server password (which uses the secure Argon2 hash) via the
# built-in interactive command, and then creates and enables a systemd service
# to run JupyterLab bound to all interfaces (0.0.0.0) on port 8888.
#
# The "No web browser found" warning is expected on headless servers.
#
# Usage (as root):
#   chmod +x install_jupyter_lab_service.sh
#   ./install_jupyter_lab_service.sh
#
# After the script completes, open an incognito/private browser and navigate to:
#   http://<your-server-ip>:8888
# Log in using the password you set.

set -e

### 1. Update package lists and install prerequisites
echo "Updating package lists..."
sudo apt-get update

echo "Installing python3.11-venv, Node.js, and npm..."
sudo apt-get install -y python3.11-venv nodejs npm

### 2. Ensure the 'node' command exists (JupyterLab requires 'node', not just 'nodejs')
if ! command -v node >/dev/null 2>&1; then
    echo "'node' command not found. Creating a symlink from 'nodejs'..."
    sudo ln -s "$(command -v nodejs)" /usr/bin/node
fi

### 3. Create a virtual environment
VENV_DIR="/root/jupyter_env"
echo "Creating virtual environment at ${VENV_DIR}..."
python3 -m venv "${VENV_DIR}"

### 4. Activate the virtual environment and install Jupyter packages
echo "Activating virtual environment and installing Jupyter packages..."
source "${VENV_DIR}/bin/activate"
pip install --upgrade pip setuptools wheel
pip install jupyter jupyter_server notebook nbclassic argon2-cffi jupyterlab

### 5. Set the Jupyter Server password interactively
echo "Please set your Jupyter Server password."
echo "When prompted, enter your desired password (and retype to verify):"
jupyter server password
# This writes the secure Argon2-based hash to ~/.jupyter/jupyter_server_config.json

### 6. Create a systemd service file to run JupyterLab
SERVICE_FILE="/etc/systemd/system/jupyter_lab.service"
cat <<EOF > "${SERVICE_FILE}"
[Unit]
Description=Jupyter Lab
After=network.target

[Service]
Type=simple
# This service runs JupyterLab as root (for demo purposes); in production, consider a dedicated non-root user.
WorkingDirectory=/root
ExecStart=${VENV_DIR}/bin/jupyter lab --allow-root --ip=0.0.0.0 --port=8888
Restart=always

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "${SERVICE_FILE}"
echo "Created systemd service at ${SERVICE_FILE}"

### 7. Reload systemd and enable & start the service
echo "Reloading systemd daemon and enabling the Jupyter Lab service..."
systemctl daemon-reload
systemctl enable jupyter_lab.service
systemctl start jupyter_lab.service

echo "JupyterLab is now running as a service."
echo "Open your browser and navigate to http://<your-server-ip>:8888"
echo "Log in using the password you provided."
