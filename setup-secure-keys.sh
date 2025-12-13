#!/bin/bash

# GitHub Auth Toolkit - Secure Key Setup
# Encrypts GitHub App PEM key with hashed password

set -euo pipefail

echo "=== GitHub Auth Toolkit - Secure Key Setup ==="
echo

# Function to detect OS and install dependencies
install_dependencies() {
    local missing_deps=()
    
    # Check which dependencies are missing
    for cmd in gpg mkpasswd; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    # If no missing dependencies, return
    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo "Missing dependencies: ${missing_deps[*]}"
    echo "Attempting to install automatically..."
    
    # Detect OS and package manager
    if command -v dnf >/dev/null 2>&1; then
        # RHEL/CentOS/Fedora with dnf
        echo "Detected RHEL/CentOS/Fedora (dnf)"
        sudo dnf install -y gnupg2 mkpasswd
    elif command -v yum >/dev/null 2>&1; then
        # RHEL/CentOS with yum
        echo "Detected RHEL/CentOS (yum)"
        sudo yum install -y gnupg2 mkpasswd
    elif command -v apt >/dev/null 2>&1; then
        # Debian/Ubuntu
        echo "Detected Debian/Ubuntu (apt)"
        sudo apt update && sudo apt install -y gnupg2 whois
    elif command -v pacman >/dev/null 2>&1; then
        # Arch Linux
        echo "Detected Arch Linux (pacman)"
        sudo pacman -S --noconfirm gnupg
    elif command -v zypper >/dev/null 2>&1; then
        # openSUSE
        echo "Detected openSUSE (zypper)"
        sudo zypper install -y gpg2 mkpasswd
    elif command -v apk >/dev/null 2>&1; then
        # Alpine Linux
        echo "Detected Alpine Linux (apk)"
        sudo apk add --no-cache gnupg mkpasswd
    else
        echo "Error: Could not detect package manager"
        echo "Please install manually:"
        echo "  RHEL/CentOS: dnf install -y gnupg2 mkpasswd"
        echo "  Debian/Ubuntu: apt install -y gnupg2 whois"
        echo "  Arch: pacman -S gnupg"
        echo "  Alpine: apk add gnupg mkpasswd"
        exit 1
    fi
    
    # Verify installation
    echo "Verifying installation..."
    for cmd in "${missing_deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Error: Failed to install $cmd"
            echo "Please install manually and try again"
            exit 1
        fi
    done
    
    echo "✓ Dependencies installed successfully"
}

# Check and install dependencies
install_dependencies

# Configuration
SALT_VALUE="ghauth24"  # Max 16 chars for mkpasswd
KEYS_DIR="./keys"

# Check if PEM file argument is provided
if [[ $# -eq 0 ]]; then
    echo "Error: Missing required PEM file argument"
    echo ""
    echo "Usage: $0 <github-app-private-key.pem>"
    echo "Example: $0 ./my-github-app.pem"
    echo ""
    echo "IMPORTANT: Make sure to select the correct PEM key file!"
    echo "- Use the PRIVATE key file (ends with .pem)"
    echo "- NOT the public key or certificate"
    echo "- The file should contain '-----BEGIN RSA PRIVATE KEY-----' or similar"
    echo ""
    echo "Get your GitHub App PEM key from:"
    echo "GitHub → Settings → Developer settings → GitHub Apps → Your App → Generate private key"
    echo ""
    echo "Available .pem files in current directory:"
    find . -maxdepth 2 -name "*.pem" -type f 2>/dev/null | head -5 || echo "  (no .pem files found)"
    exit 1
fi

PEM_FILE="$1"

if [[ ! -f "$PEM_FILE" ]]; then
    echo "Error: PEM file '$PEM_FILE' not found!"
    echo ""
    echo "IMPORTANT: Make sure to select the correct PEM key file!"
    echo "- Use the PRIVATE key file (ends with .pem)"
    echo "- NOT the public key or certificate"
    echo "- The file should contain '-----BEGIN RSA PRIVATE KEY-----' or similar"
    echo ""
    echo "Available .pem files in current directory:"
    find . -maxdepth 2 -name "*.pem" -type f 2>/dev/null | head -5 || echo "  (no .pem files found)"
    exit 1
fi

echo "Setting up secure encryption for: $PEM_FILE"
echo

# Create keys directory
mkdir -p "$KEYS_DIR"

# Get master password
echo "Enter master password for key encryption:"
read -s MASTER_PASSWORD
echo

echo "Confirm master password:"
read -s MASTER_PASSWORD_CONFIRM
echo

if [[ "$MASTER_PASSWORD" != "$MASTER_PASSWORD_CONFIRM" ]]; then
    echo "Error: Passwords do not match"
    exit 1
fi

# Generate password hash
echo "Generating secure password hash..."
PASSWORD_HASH=$(echo "$MASTER_PASSWORD" | mkpasswd -m sha-512 -S "$SALT_VALUE")

# Verify hash by generating it again with confirmation password
echo "Verifying password hash..."
PASSWORD_HASH_CONFIRM=$(echo "$MASTER_PASSWORD_CONFIRM" | mkpasswd -m sha-512 -S "$SALT_VALUE")

if [[ "$PASSWORD_HASH" != "$PASSWORD_HASH_CONFIRM" ]]; then
    echo "Error: Password hashes do not match - passwords were entered differently"
    exit 1
fi

echo "✓ Password hash verified successfully"

# Use the PASSWORD HASH as the encryption key (no need to store real password!)
ENCRYPTION_PASSPHRASE=$(echo -n "$PASSWORD_HASH" | sha256sum | cut -d' ' -f1)

# Encrypt the PEM key
ENCRYPTED_PEM="$KEYS_DIR/github-app.pem.gpg"
echo "Encrypting PEM key..."

# Remove existing encrypted file if it exists
if [[ -f "$ENCRYPTED_PEM" ]]; then
    echo "Removing existing encrypted file: $ENCRYPTED_PEM"
    rm -f "$ENCRYPTED_PEM"
fi

if echo "$ENCRYPTION_PASSPHRASE" | gpg --symmetric --cipher-algo AES256 --batch --yes --passphrase-fd 0 --output "$ENCRYPTED_PEM" "$PEM_FILE" 2>/dev/null; then
    echo "✓ PEM key encrypted successfully: $ENCRYPTED_PEM"
else
    echo "Error: Failed to encrypt PEM key"
    exit 1
fi

# Create environment configuration file
ENV_FILE="./github-app.env"
cat > "$ENV_FILE" <<'EOF'
# GitHub App Configuration
# Source this file: source ./github-app.env

export GITHUB_APP_ID="YOUR_APP_ID_HERE"
export GITHUB_CLIENT_ID="YOUR_CLIENT_ID_HERE"
EOF

# Add the dynamic values with proper escaping
cat >> "$ENV_FILE" <<EOF
export GITHUB_APP_PRIVATE_KEY_ENCRYPTED="$(pwd)/$ENCRYPTED_PEM"
export MASTER_PASSWORD_HASH='$PASSWORD_HASH'
export SALT_VALUE="$SALT_VALUE"

# No manual password needed - hash is used directly for automation!
EOF

# Create setup information file
SETUP_INFO="./SETUP-INFO.txt"
cat > "$SETUP_INFO" <<EOF
=== GitHub Auth Toolkit Setup Complete ===

Generated: $(date)
Salt: $SALT_VALUE
Password Hash: $PASSWORD_HASH

SECURITY NOTES:
✓ Password hash is safe to store/commit
✓ Encrypted PEM key is safe to store/commit  
✓ Hash is used directly - no manual password needed after setup

NEXT STEPS:
1. Edit github-app.env and set your GITHUB_APP_ID and GITHUB_CLIENT_ID
2. source ./github-app.env
3. ./github-app-auth.sh (auto-discovers Installation ID and generates access token)
4. ./clone-repos.sh repos.txt (clones your repositories)

FILES CREATED:
- $ENCRYPTED_PEM (encrypted PEM key - safe to store)
- $ENV_FILE (environment config - safe to store)
- $SETUP_INFO (this file - safe to store)

ORIGINAL PEM FILE: $PEM_FILE
(You can delete the original PEM file now - encrypted version is sufficient)

For help: https://github.com/fueledbybits/github-auth-toolkit
EOF

echo
echo "=== Setup Complete ==="
echo "✓ Encrypted PEM key: $ENCRYPTED_PEM"
echo "✓ Environment config: $ENV_FILE"
echo "✓ Setup info: $SETUP_INFO"
echo
echo "Next steps:"
echo "1. Edit $ENV_FILE and set your GitHub App ID and Client ID"
echo "2. source $ENV_FILE"
echo "3. ./github-app-auth.sh (auto-discovers Installation ID)"
echo "4. ./clone-repos.sh your-repos.txt"
echo
echo "Security: Fully automated after setup - no passwords needed at runtime!"

# Clean up sensitive variables
unset MASTER_PASSWORD MASTER_PASSWORD_CONFIRM ENCRYPTION_PASSPHRASE