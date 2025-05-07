#!/bin/bash

# Exit on error
set -e

# === CONFIGURATION ===
SHARE_NAME="csv_import"
SHARE_PATH="/srv/samba/$SHARE_NAME"
WINDOWS_GROUP_NAME="sambasharegrp"
DEST_DIR="$SHARE_PATH/"

# Azure service principal credentials
AZ_CLIENT_ID="$1"
AZ_CLIENT_SECRET="$2"
AZ_TENANT_ID="$3"
AZURE_ACR_NAME="$4"   # ACR name only (no .azurecr.io)

# installing Sudo
echo "=== Installing sudo ==="
if ! command -v sudo &> /dev/null; then
    apt-get update
    su -c "apt-get install -y sudo"
fi

# installing all the required packages
echo "=== Installing Docker ==="
if ! command -v docker &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
fi

echo "=== Installing Azure CLI ==="
if ! command -v az &> /dev/null; then
    sudo curl -sL https://aka.ms/InstallAzureCLIDeb | bash
fi

echo "=== Installing Samba ==="
if ! command -v smbd &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y libcups2 samba samba-common cups
fi

# Create shared directory
echo "=== Creating Samba Folder ==="
sudo mkdir -p "$DEST_DIR"
sudo chown -R root:users "$DEST_DIR"
sudo chmod -R ug+rwx,o+rx-w "$DEST_DIR"

# Add Samba share to config if not already present
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
    " | sudo tee -a /etc/samba/smb.conf > /dev/null
        sudo systemctl restart smbd
fi

# login into the service principal, then into ACR and pull all the latest images
echo "=== Logging in with service principal ==="
sudo az login --service-principal \
    --username "$AZ_CLIENT_ID" \
    --password "$AZ_CLIENT_SECRET" \
    --tenant "$AZ_TENANT_ID"

echo "Logging into Azure Container Registry and pulling 'latest' images..."
sudo az acr login --name "$AZURE_ACR_NAME"

REPOS=$(sudo az acr repository list --name "$AZURE_ACR_NAME" --output tsv)

for REPO in $REPOS; do
    FULL_IMAGE="$AZURE_ACR_NAME.azurecr.io/$REPO:latest"
    echo "Pulling $FULL_IMAGE"
    sudo docker pull "$FULL_IMAGE"
done

echo "Setup complete! Samba shared folder configured at $SHARE_PATH and images pulled"
