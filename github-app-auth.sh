#!/bin/bash

# GitHub Auth Toolkit - Authentication Module
# Generates GitHub App installation tokens for secure repository access

set -euo pipefail

echo "=== GitHub Auth Toolkit - Authentication ==="

# Function to detect OS and install dependencies
install_dependencies() {
    local missing_deps=()
    
    # Check which dependencies are missing
    for cmd in openssl jq curl base64; do
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
        sudo dnf install -y openssl jq curl coreutils
    elif command -v yum >/dev/null 2>&1; then
        # RHEL/CentOS with yum
        echo "Detected RHEL/CentOS (yum)"
        sudo yum install -y openssl jq curl coreutils
    elif command -v apt >/dev/null 2>&1; then
        # Debian/Ubuntu
        echo "Detected Debian/Ubuntu (apt)"
        sudo apt update && sudo apt install -y openssl jq curl coreutils
    elif command -v pacman >/dev/null 2>&1; then
        # Arch Linux
        echo "Detected Arch Linux (pacman)"
        sudo pacman -S --noconfirm openssl jq curl coreutils
    elif command -v zypper >/dev/null 2>&1; then
        # openSUSE
        echo "Detected openSUSE (zypper)"
        sudo zypper install -y openssl jq curl coreutils
    elif command -v apk >/dev/null 2>&1; then
        # Alpine Linux
        echo "Detected Alpine Linux (apk)"
        sudo apk add --no-cache openssl jq curl coreutils
    else
        echo "Error: Could not detect package manager"
        echo "Please install manually:"
        echo "  RHEL/CentOS: dnf install -y openssl jq curl coreutils"
        echo "  Debian/Ubuntu: apt install -y openssl jq curl coreutils"
        echo "  Arch: pacman -S openssl jq curl coreutils"
        echo "  Alpine: apk add openssl jq curl coreutils"
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
    echo
}

# Check and install dependencies
install_dependencies

# Load configuration
if [[ ! -f "./github-app.env" ]]; then
    echo "Error: github-app.env not found!"
    echo "Run ./setup-secure-keys.sh first to create configuration."
    exit 1
fi

source ./github-app.env

# Validate required configuration
if [[ -z "$GITHUB_APP_ID" || "$GITHUB_APP_ID" == "YOUR_APP_ID_HERE" ]]; then
    echo "Error: GITHUB_APP_ID not set in github-app.env"
    echo "Edit github-app.env and set your GitHub App ID"
    exit 1
fi

if [[ -z "$GITHUB_CLIENT_ID" || "$GITHUB_CLIENT_ID" == "YOUR_CLIENT_ID_HERE" ]]; then
    echo "Error: GITHUB_CLIENT_ID not set in github-app.env"
    echo "Edit github-app.env and set your GitHub Client ID"
    exit 1
fi

if [[ ! -f "$GITHUB_APP_PRIVATE_KEY_ENCRYPTED" ]]; then
    echo "Error: Encrypted GitHub App private key not found at $GITHUB_APP_PRIVATE_KEY_ENCRYPTED"
    echo "Run ./setup-secure-keys.sh first to encrypt your PEM key."
    exit 1
fi

if [[ -z "$MASTER_PASSWORD_HASH" ]]; then
    echo "Error: MASTER_PASSWORD_HASH not set in github-app.env"
    echo "Run ./setup-secure-keys.sh first to generate password hash."
    exit 1
fi

echo "Authenticating with GitHub App..."
echo "App ID: $GITHUB_APP_ID"
echo "Client ID: $GITHUB_CLIENT_ID"

# Decrypt PEM key
echo "Decrypting GitHub App PEM key using stored hash..."
encryption_passphrase=$(echo -n "$MASTER_PASSWORD_HASH" | sha256sum | cut -d' ' -f1)
temp_key="/tmp/github-app-$$.pem"

if ! echo "$encryption_passphrase" | gpg --decrypt --quiet --batch --passphrase-fd 0 "$GITHUB_APP_PRIVATE_KEY_ENCRYPTED" > "$temp_key" 2>/dev/null; then
    echo "Error: Failed to decrypt PEM key"
    rm -f "$temp_key"
    exit 1
fi

echo "✓ PEM key decrypted successfully"

# Auto-discover Installation ID
echo "Auto-discovering Installation ID..."

# Generate JWT using Client ID 
header='{"alg":"RS256","typ":"JWT"}'
now=$(date +%s)
exp=$((now + 600))
payload="{\"iat\":$now,\"exp\":$exp,\"iss\":\"$GITHUB_CLIENT_ID\"}"

header_b64=$(echo -n "$header" | base64 -w 0 | tr -d '=')
payload_b64=$(echo -n "$payload" | base64 -w 0 | tr -d '=')
signature=$(echo -n "$header_b64.$payload_b64" | openssl dgst -sha256 -sign "$temp_key" | base64 -w 0 | tr -d '=')

JWT="$header_b64.$payload_b64.$signature"

echo "Generated JWT using Client ID, querying installations..."

# Get installations
INSTALLATIONS_RESPONSE=$(curl -s -H "Authorization: Bearer $JWT" \
     -H "Accept: application/vnd.github.v3+json" \
     "https://api.github.com/app/installations")

echo "API Response:"
echo "$INSTALLATIONS_RESPONSE" | jq '.'

# Extract first installation ID
INSTALLATION_ID=$(echo "$INSTALLATIONS_RESPONSE" | jq -r '.[0].id // empty')

if [[ -n "$INSTALLATION_ID" && "$INSTALLATION_ID" != "null" ]]; then
    echo "✓ Auto-discovered Installation ID: $INSTALLATION_ID"
else
    echo "Error: Could not auto-discover Installation ID"
    echo "Make sure your GitHub App is installed on at least one repository"
    rm -f "$temp_key"
    exit 1
fi

# Generate new JWT for installation access token
echo "Generating JWT for installation access token..."
now=$(date +%s)
exp=$((now + 600))
payload="{\"iat\":$now,\"exp\":$exp,\"iss\":\"$GITHUB_CLIENT_ID\"}"

payload_b64=$(echo -n "$payload" | base64 -w 0 | tr -d '=')
signature=$(echo -n "$header_b64.$payload_b64" | openssl dgst -sha256 -sign "$temp_key" | base64 -w 0 | tr -d '=')

JWT="$header_b64.$payload_b64.$signature"

# Get installation access token
echo "Requesting installation access token..."
ACCESS_TOKEN=$(curl -s -X POST \
    -H "Authorization: Bearer $JWT" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens" | \
    jq -r '.token')

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
    echo "Error: Failed to get installation access token"
    echo "Check your App ID and Client ID in github-app.env"
    rm -f "$temp_key"
    exit 1
fi

echo "✓ Successfully obtained GitHub access token"

# Configure git to use the token globally
git config --global credential.helper store
echo "https://x-access-token:$ACCESS_TOKEN@github.com" > ~/.git-credentials

# Export token for use by other scripts
export GITHUB_ACCESS_TOKEN="$ACCESS_TOKEN"

# Save token to temporary file for clone-repos.sh
echo "$ACCESS_TOKEN" > /tmp/github-access-token

echo "✓ Git configured for GitHub access"
echo "✓ Token exported as GITHUB_ACCESS_TOKEN"
echo "✓ Ready to clone repositories"

# Clean up temporary PEM key
rm -f "$temp_key"

echo
echo "Token expires in 1 hour. Re-run this script to refresh."
echo "Next: ./clone-repos.sh your-repos.txt"