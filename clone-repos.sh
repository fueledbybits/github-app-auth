#!/bin/bash

# GitHub Auth Toolkit - Repository Cloning Module
# Clones repositories using authenticated GitHub access

set -euo pipefail

echo "=== GitHub Auth Toolkit - Repository Cloning ==="

: <<'COMMENT'
# Install git if it doesn't exist
if ! command -v git &> /dev/null; then
    echo "Git not found, installing..."
    if command -v dnf &> /dev/null; then
        dnf install -y git
    elif command -v yum &> /dev/null; then
        yum install -y git
    elif command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y git
    elif command -v pacman &> /dev/null; then
        pacman -S --noconfirm git
    elif command -v zypper &> /dev/null; then
        zypper install -y git
    else
        echo "Error: No supported package manager found. Please install git manually."
        exit 1
    fi
    echo "Git installed successfully."
else
    echo "Git is already installed."
fi
COMMENT


# Check for help first
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [repos-file] [default-destination]"
    echo ""
    echo "Arguments:"
    echo "  repos-file         File containing repository list (default: repos.txt)"
    echo "  default-destination Default clone destination (default: ./repositories)"
    echo ""
    echo "Repository file format:"
    echo "  user/repo destination"
    echo "  user/repo	destination      # Tab separator also works"
    echo "  user/repo                    # Uses default destination"
    echo ""
    echo "Examples:"
    echo "  ./clone-repos.sh"
    echo "  ./clone-repos.sh my-repos.txt"
    echo "  ./clone-repos.sh my-repos.txt /opt/code"
    echo ""
    echo "Sample repos.txt:"
    echo "  microsoft/vscode /opt/editors/vscode"
    echo "  torvalds/linux /usr/src/linux"
    echo "  kubernetes/kubernetes"
    exit 0
fi

# Require repos file to be specified
if [[ $# -eq 0 ]]; then
    echo "❌ No repository file specified!"
    echo ""
    echo "💡 Usage: $0 <repos-file> [default-destination]"
    echo "   Example: $0 repos.txt"
    echo "   Example: $0 my-repos.txt /opt/code"
    echo ""
    echo "ℹ️  Run '$0 --help' for detailed information"
    exit 1
fi

# Configuration
REPOS_FILE="$1"
DEFAULT_DESTINATION="${2:-./repositories}"

if [[ ! -f "$REPOS_FILE" ]]; then
    echo "❌ Repository file '$REPOS_FILE' not found!"
    echo ""
    echo "📝 Please create a repository list file with this format:"
    echo "   user/repository destination"
    echo "   user/repository             # Uses default destination"
    echo ""
    echo "📋 Example repos.txt:"
    echo "   microsoft/vscode /opt/editors/vscode"
    echo "   torvalds/linux /usr/src/linux" 
    echo "   kubernetes/kubernetes"
    echo ""
    echo "💡 Usage: $0 [repos-file] [default-destination]"
    echo "   Example: $0 my-repos.txt /opt/code"
    echo ""
    echo "ℹ️  Run '$0 --help' for detailed information"
    exit 1
fi

# Check if authentication was run
if [[ ! -f "/tmp/github-access-token" ]] && [[ -z "${GITHUB_ACCESS_TOKEN:-}" ]]; then
    echo "Error: No GitHub access token found!"
    echo "Run ./github-app-auth.sh first to authenticate."
    exit 1
fi

if [[ -n "${GITHUB_ACCESS_TOKEN:-}" ]]; then
    ACCESS_TOKEN="$GITHUB_ACCESS_TOKEN"
elif [[ -f "/tmp/github-access-token" ]]; then
    ACCESS_TOKEN=$(cat /tmp/github-access-token)
else
    echo "Error: Could not retrieve access token"
    exit 1
fi

echo "Repository file: $REPOS_FILE"
echo "Default destination: $DEFAULT_DESTINATION"
echo ""


mkdir -p "$DEFAULT_DESTINATION"


clone_or_update_repo() {
    local repo="$1"
    local destination="$2"
    
    echo "Processing: $repo → $destination"
    
    # Create destination directory
    mkdir -p "$(dirname "$destination")"
    
    if [[ -d "$destination/.git" ]]; then
        echo "  Git repository exists, checking if it's the same repo..."
        cd "$destination"
        
        # Get current repository URL
        current_repo=$(git remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||' | sed 's|\.git$||')
        expected_repo="$repo"
        
        if [[ "$current_repo" == "$expected_repo" ]]; then
            echo "  ✓ Same repository, updating..."
            # Ensure remote URL uses credentials file (no embedded token)
            git remote set-url origin "https://github.com/$repo.git"
            
            # Handle local changes automatically
            if ! git diff-index --quiet HEAD --; then
                echo "  Local changes detected, stashing..."
                git stash push -m "Auto-stash before update $(date)"
            fi
            
            if git pull; then
                echo "  ✓ Updated successfully"
                # Try to restore stashed changes if any
                if git stash list | grep -q "Auto-stash before update"; then
                    echo "  Attempting to restore local changes..."
                    if git stash pop; then
                        echo "  ✓ Local changes restored"
                    else
                        echo "  ⚠ Merge conflicts in local changes - check manually"
                    fi
                fi
            else
                echo "  ⚠ Update failed, but continuing..."
            fi
        else
            echo "  ✗ Error: Different repository found!"
            echo "    Expected: $expected_repo"
            echo "    Found:    $current_repo"
            echo "    Please remove '$destination' manually or choose different destination"
            cd - > /dev/null
            return 1
        fi
        cd - > /dev/null
    elif [[ -d "$destination" ]]; then

        if [[ -z "$(ls -A "$destination" 2>/dev/null)" ]]; then
            echo "  Directory exists but is empty, proceeding with clone..."

            rmdir "$destination"
            echo "  Cloning repository..."
            # Create parent directory if needed
            mkdir -p "$(dirname "$destination")"
            
            if git clone "https://x-access-token:$ACCESS_TOKEN@github.com/$repo.git" "$destination"; then
                echo "  ✓ Cloned successfully"
                # Configure remote URL WITHOUT token - let credentials file handle auth
                cd "$destination"
                git remote set-url origin "https://github.com/$repo.git"
                cd - > /dev/null
            else
                echo "  ✗ Clone failed: $repo"
                return 1
            fi
        else
            echo "  ✗ Error: Directory '$destination' already exists  but is not a git repository, and it has files already."
            echo "    Please remove it manually or choose a different destination"
            echo "    Contents: $(ls -la "$destination" 2>/dev/null | wc -l) items"
            return 1
        fi
    else
        echo "  Cloning repository..."
        # Create parent directory if needed
        mkdir -p "$(dirname "$destination")"
        
        if git clone "https://x-access-token:$ACCESS_TOKEN@github.com/$repo.git" "$destination"; then
            echo "  ✓ Cloned successfully"
            # Configure remote URL WITHOUT token - let credentials file handle auth
            cd "$destination"
            git remote set-url origin "https://github.com/$repo.git"
            cd - > /dev/null
        else
            echo "  ✗ Clone failed: $repo"
            return 1
        fi
    fi
}

# Process repositories
success_count=0
error_count=0

echo "Processing repositories..."
echo


mapfile -t repo_lines < "$REPOS_FILE"

for line in "${repo_lines[@]}"; do

    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Parse repository and destination (supports space and tab separators)
    if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
        # Format: "user/repo destination" or "user/repo	destination"
        repo="${BASH_REMATCH[1]}"
        destination="${BASH_REMATCH[2]}"
    else

        repo="$line"
        destination="$DEFAULT_DESTINATION/$(basename "$repo")"
    fi
    
    # Clean up whitespace and trailing slashes from repo name
    repo=$(echo "$repo" | xargs | sed 's|/*$||')
    destination=$(echo "$destination" | xargs)
    
    # Validate repository format
    if [[ ! "$repo" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
        echo "⚠ Skipping invalid repository format: $repo"
        ((error_count++))
        continue
    fi
    

    if clone_or_update_repo "$repo" "$destination"; then
        success_count=$((success_count + 1))
    else
        error_count=$((error_count + 1))
    fi
    
    echo
done


echo "=== Summary ==="
echo "✓ Successful: $success_count repositories"
if [[ $error_count -gt 0 ]]; then
    echo "✗ Failed: $error_count repositories"
fi
echo

if [[ $error_count -eq 0 ]]; then
    echo "All repositories processed successfully!"
    exit 0
else
    echo "Some repositories failed. Check the output above for details."
    exit 1
fi