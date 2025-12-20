# GitHub Auth Toolkit

Tired of managing SSH keys for automated GitHub access? This toolkit makes it simple and secure.

## What it does

- Securely clone GitHub repositories in scripts and automation
- Uses GitHub Apps (the modern way) instead of SSH keys
- Encrypts everything so you can safely store configs in Git
- Works great for CI/CD, server provisioning, or any automation

## Quick Setup

### 1. Create a GitHub App

Go to GitHub → Settings → Developer settings → GitHub Apps → New GitHub App

Set these permissions:
- Contents: Read
- Metadata: Read

Download the private key file and install the app on your repositories.

### 2. Encrypt your key

```bash
git clone https://github.com/fueledbybits/github-app-auth.git
cd github-app-auth
chmod +x *.sh

Download and copy your github app pem key.

Generate Encrypted key
    ./setup-secure-keys.sh your-app-downloaded-key.pem

Enter a password when prompted. The script encrypts your key and creates a config file.

Remove your Original Key:
    rm your-app-downloaded-key.pem
```

### 3. Add your App details

Edit `github-app.env` and add your App ID and Client ID (both found in your GitHub App settings).

### 4. Create file with your repositories to clone.

Create `repos.txt`:
Add inf in the following format:
```
user/repository /path/where/you/want/it

example:
your-company/your-repo ./code/project
```

### 5. Run it

```bash
source ./github-app.env
./github-app-auth.sh
./clone-repos.sh repos.txt
```

Afterwards you can manage each repo individually by using normal git commands like `git pull origin main`.

**Token Management:**
- GitHub App tokens expire after 1 hour
- When expired, simply run `git-auth` from anywhere to renew
- All repositories will automatically use the new token
- No need to update individual repositories manually

**Available Commands:**
- `git-auth` - Renew GitHub authentication token
- `git-clone <repos-file>` - Clone/update all repositories from file


## How the repo list works

Simple format - repository name, then where to put it:

```
user/repository /path/where/you/want/it
user/repository	/path/with/tab/separator
user/repository                    # goes to ./repositories/repository
```

Comments work too:
```
# Production repos
company/frontend /var/www/frontend
company/backend /var/www/backend

# Development stuff  
facebook/react ./dev/react
```

## What's secure about this

Your GitHub App private key gets encrypted with a password. The password itself gets hashed. Everything can be safely stored in Git except your actual password.

When you run the auth script, it:
1. Decrypts your key using the password hash
2. Gets a temporary token from GitHub (expires in 1 hour)
3. Uses that token to clone repositories
4. Cleans up everything when done

## Common use cases

**Server provisioning:**
```bash
# In your server setup script
source /opt/tools/github-app.env
/opt/tools/github-app-auth-clean.sh
/opt/tools/clone-repos.sh /opt/tools/server-repos.txt
```

**CI/CD pipelines:**
```bash
# In Jenkins, GitHub Actions, etc.
source ./github-app.env
./github-app-auth-clean.sh
./clone-repos.sh build-deps.txt /workspace
```

**Development environment setup:**
```bash
# Clone all your company's repos
./clone-repos.sh company-repos.txt ~/code
```

## Troubleshooting

**"Failed to decrypt PEM key"** - You entered the wrong password, or the encrypted file is corrupted.

**"Could not auto-discover Installation ID"** - Your GitHub App isn't installed on any repositories, or the App ID/Client ID is wrong.

**"Different repository found"** - The destination folder already contains a different Git repository. Remove it manually or pick a different location.

**"Directory exists but is not a git repository"** - There are files in the destination folder. The script won't delete them automatically - clean up manually.

***fatal: repository 'https://github.com/#####.git/' not found***
Please check if your app is allowed access into this repository.

## Why GitHub Apps instead of SSH keys

GitHub Apps are the modern way to authenticate automation:
- Tokens expire automatically (more secure)
- Fine-grained permissions per repository
- Easy to revoke access
- Works in any environment (no SSH setup needed)
- GitHub's recommended approach for automation

## Making it even more secure

The basic setup stores an encrypted password hash, which is pretty secure. But if you're in a corporate environment or want to go further, you can modify the scripts to fetch the password from enterprise password managers:

**AWS Secrets Manager:**
```bash
# Replace the password hash with:
MASTER_PASSWORD=$(aws secretsmanager get-secret-value --secret-id github-master-password --query SecretString --output text)
```

**HashiCorp Vault:**
```bash
# Get password from Vault:
MASTER_PASSWORD=$(vault kv get -field=password secret/github-auth)
```

**Azure Key Vault:**
```bash
# Fetch from Azure:
MASTER_PASSWORD=$(az keyvault secret show --vault-name MyVault --name github-password --query value -o tsv)
```

**Kubernetes Secrets:**
```bash
# In a pod, read from mounted secret:
MASTER_PASSWORD=$(cat /etc/secrets/github-password)
```

Just modify the `github-app-auth-clean.sh` script to fetch the password from your preferred secret store instead of using the hash. This way, passwords can be rotated centrally and you get full audit trails of who accessed what.


## Issues

Found a bug or have a suggestion? Open an issue on GitHub.