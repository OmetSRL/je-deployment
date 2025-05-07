#!/bin/bash

# Exit on error
set -e

# === CONFIGURATION ===
SHARE_NAME="csv_import"
SHARE_PATH="/srv/samba/$SHARE_NAME"
SAMBA_USER="smbuser"
SAMBA_PASS="smbpassword"
GROUP_NAME="sambasharegrp"
AZURE_ACR_NAME="youracrname"   # ACR name only (no .azurecr.io)
DEST_DIR="$SHARE_PATH/images"

# Azure service principal credentials
AZ_CLIENT_ID="your-client-id"
AZ_CLIENT_SECRET="your-client-secret"
AZ_TENANT_ID="your-tenant-id"

# installing Sudo
echo "=== Installing sudo ==="
if ! command -v sudo &> /dev/null; then
    apt-get update
    su -c "apt-get install -y sudo"
fi

# installing Docker and dependencies
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

echo "=== Creating Samba Group and Folder ==="
# Create group if needed
if ! getent group "$GROUP_NAME" > /dev/null; then
    sudo groupadd "$GROUP_NAME"
fi

# Create Samba user
if ! id "$SAMBA_USER" &> /dev/null; then
    sudo useradd -M -s /sbin/nologin "$SAMBA_USER"
fi
sudo usermod -aG "$GROUP_NAME" "$SAMBA_USER"
echo -e "$SAMBA_PASS\n$SAMBA_PASS" | smbpasswd -a -s "$SAMBA_USER"

# Create shared directory
sudo mkdir -p "$DEST_DIR"
sudo chown -R root:$GROUP_NAME "$SHARE_PATH"
sudo chmod -R 2775 "$SHARE_PATH"
sudo find "$SHARE_PATH" -type d -exec chmod 2775 {} \;

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
    valid users = @$GROUP_NAME
    " | sudo tee -a /etc/samba/smb.conf > /dev/null
    sudo systemctl restart smbd
fi

# login into ACR and pulling all the latest images
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

echo "Setup complete! Samba share configured and images pulled"
