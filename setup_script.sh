#!/bin/bash

# Usage: ./je-deployment/setup_script.sh <dockerhub-username> <dockerhub-password>


# Exit on error
set -e

# === CONFIGURATION ===
SHARE_NAME="$3"
SHARE_PATH="/home/shares/$SHARE_NAME"
WINDOWS_GROUP_NAME="windowsgroup"
DEST_DIR="$SHARE_PATH/"

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# installing all the required packages
echo "=== Installing Docker ==="
if ! command -v docker &> /dev/null; then
    apt-get update
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Create keyring directory if not exists
    mkdir -p /etc/apt/keyrings

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    # Add the Docker APT repository for Debian
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
fi

echo "=== Installing Samba ==="
if ! command -v smbd &> /dev/null; then
    apt-get update
    apt-get install -y libcups2 samba samba-common cups
fi

# create shared directory
echo "=== Creating and configurating Samba Folder ==="
mkdir -p "$DEST_DIR"
chown -R root:users "$DEST_DIR"
chmod -R ug+rwx,o+rx-w "$DEST_DIR"

# add Samba share to config if not already present
# execute permissions required on directory mask to cd into them
if ! grep -q "^\[$SHARE_NAME\]" /etc/samba/smb.conf; then
    echo "Adding Samba configuration..."
    echo "
[global]
    workgroup = $GROUP_NAME
    server string = Samba Server %v
    netbios name = debian
    security = user
    map to guest = bad user
    dns proxy = no

[$SHARE_NAME]
    path = $SHARE_PATH
    force group = users
    create mask = 0660
    directory mask = 0771
    browsable =yes
    writable = yes
    guest ok = yes
    " | tee -a /etc/samba/smb.conf > /dev/null
        systemctl restart smbd
fi


echo "=== Logging into Docker Hub ==="
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <username> <password>"
  exit 1
fi

DOCKER_USERNAME="$1"
DOCKER_PASSWORD="$2"

echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin

if [ $? -eq 0 ]; then
  echo "Docker login successful"
else
  echo "Docker login failed" >&2
  exit 1
fi

echo "=== Installing Python if necessary ==="
# Check for Python 3
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is not installed."

    # Attempt to install Python 3 (Debian/Ubuntu)
    if [ -f /etc/debian_version ]; then
        echo "Installing Python 3 using apt..."
        apt update
        apt install -y python3
    else
        echo "Unsupported OS for auto-install. Please install Python 3 manually."
        exit 1
    fi
fi

echo "=== Creating virtual env and installing dependencies ==="

echo "Installing python3-venv and python3-pip if they are missing"

apt update
apt install -y python3-venv python3-pip

# i move inside the folder
cd je-deployment
# Create virtual environment if it doesn't exist
if [ ! -d ".venv" ]; then
    python3 -m venv ".venv"
fi
source .venv/bin/activate

pip install --upgrade pip
pip install -r requirements.txt

# launching the script
python dockercompose_generator.py $DOCKER_USERNAME

echo "=== Python script executed ==="
# i move outside the folder again
cd ..

echo "Setup complete! Samba shared folder configured at $SHARE_PATH, created Docker compose file and logged in Docker Hub"
