#!/bin/bash

echo "This script will help you to obtain a free SSL certificate from Let's Encrypt."
echo "This script is tested on Ubuntu 18.04 and 20.04."
echo "If you are using a different OS, you may need to modify the script."
echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

# Check if Certbot is installed
if command -v certbot &>/dev/null; then
    echo "Certbot is already installed."
    certbot --version
else
    echo "Certbot is not installed. Installing..."
    sudo apt update
    sudo apt install certbot python3-certbot-apache -y
fi

REPO_PATH=$(dirname "$(readlink -f "$0")")
HOOK_DIRECTORY="$REPO_PATH/manual_hooks"

if [ -f "$REPO_PATH/.creds" ]; then
    # Get the credentials from the .creds file
    echo "Reading credentials from $REPO_PATH/.creds"

    DOMAIN=$(grep '^DOMAIN=' "$REPO_PATH/.creds" | cut -d '"' -f 2)
    CONTACT=$(grep '^CONTACT=' "$REPO_PATH/.creds" | cut -d '"' -f 2)
    CLOUD=$(grep '^CLOUD=' "$REPO_PATH/.creds" | cut -d '"' -f 2)
    API_KEY=$(grep '^API_KEY=' "$REPO_PATH/.creds" | cut -d '"' -f 2)
    ZONE_ID=$(grep '^ZONE_ID=' "$REPO_PATH/.creds" | cut -d '"' -f 2)

    echo "Domain name: $DOMAIN"
fi

if [ -z "$DOMAIN" ]; then
    # Prompt the user to enter the domain
    read -p "Enter the domain: " DOMAIN
fi

# Suggest a default email address
DEFAULT_EMAIL="info@$DOMAIN"

if [ -z "$CONTACT" ]; then
    # Prompt the user to enter the email
    read -p "Enter the email [$DEFAULT_EMAIL]: " CONTACT
fi

# Use the default email if no input provided
CONTACT="${CONTACT:-$DEFAULT_EMAIL}"

if [ -z "$CLOUD" ]; then
    # Prompt the user to select the cloud provider
    echo "Select the cloud provider:"
    echo "1. Cloudflare"
    echo "2. ArvanCloud"

    while true; do
        read -p "Enter your choice (1 or 2): " CLOUD_CHOICE
        case $CLOUD_CHOICE in
        1) CLOUD="cf"; break ;;
        2) CLOUD="arvan"; break ;;
        *) echo "Invalid choice. Please enter 1 or 2." ;;
        esac
    done
fi

case $CLOUD in
cf)
    [ -z "$API_KEY" ] && read -p "Enter your Cloudflare API key: " API_KEY
    [ -z "$ZONE_ID" ] && read -p "Enter your Cloudflare zone ID: " ZONE_ID
    ;;
arvan)
    [ -z "$API_KEY" ] && read -p "Enter your ArvanCloud API key: " API_KEY
    ;;
*)
    echo "Unknown cloud provider: '$CLOUD' (must be 'cf' or 'arvan')"
    exit 1
    ;;
esac

# Save the credentials where the hooks expect them.
# This is done on every run (also when values come from .creds),
# because the hooks read the API key from this file during issue AND renewal.
mkdir -p "$HOOK_DIRECTORY/$DOMAIN"
CREDS_FILE="$HOOK_DIRECTORY/$DOMAIN/$CLOUD.creds"
(
    umask 077
    echo "API_KEY=\"$API_KEY\"" >"$CREDS_FILE"
    [ "$CLOUD" = "cf" ] && echo "ZONE_ID=\"$ZONE_ID\"" >>"$CREDS_FILE"
)

MANUAL_HOOKS_BASE_URL="https://raw.githubusercontent.com/amirhoushmand/certbot-wildcard/main/manual_hooks"

# Download a hook only if it isn't already on disk.
# Set FORCE_DOWNLOAD=1 to fetch the latest version anyway.
ensure_hook() {
    filename=$1
    destination_path="$HOOK_DIRECTORY/$filename"

    if [ -s "$destination_path" ] && [ "$FORCE_DOWNLOAD" != "1" ]; then
        echo "Using existing hook: $destination_path"
    else
        echo "Downloading hook: $filename"
        # -f: fail on HTTP errors instead of saving a 404 page as the hook
        if ! curl -fsSL -o "$destination_path.tmp" "$MANUAL_HOOKS_BASE_URL/$filename"; then
            rm -f "$destination_path.tmp"
            echo "Failed to download the file: $MANUAL_HOOKS_BASE_URL/$filename"
            exit 1
        fi
        mv "$destination_path.tmp" "$destination_path"
    fi

    chmod +x "$destination_path"
}

ensure_hook "$CLOUD.auth.sh"
ensure_hook "$CLOUD.clean.sh"

# Note: the hooks and creds are intentionally NOT deleted afterwards.
# certbot stores these hook paths in /etc/letsencrypt/renewal/$DOMAIN.conf
# and runs them again on every "certbot renew".
certbot certonly -n --agree-tos --manual \
    --keep-until-expiring \
    --no-eff-email --preferred-challenges=dns \
    --manual-auth-hook "$HOOK_DIRECTORY/$CLOUD.auth.sh" \
    --manual-cleanup-hook "$HOOK_DIRECTORY/$CLOUD.clean.sh" \
    -m "$CONTACT" -d "$DOMAIN,*.$DOMAIN"
