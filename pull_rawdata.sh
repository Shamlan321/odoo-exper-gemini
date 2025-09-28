#!/bin/bash

# Function to check network connectivity
check_network() {
    echo "Checking network connectivity..."
    
    # Test DNS resolution
    if ! nslookup github.com >/dev/null 2>&1; then
        echo "Error: DNS resolution failed for github.com"
        echo "Trying alternative DNS servers..."
        
        # Try with different DNS servers
        if ! nslookup github.com 8.8.8.8 >/dev/null 2>&1; then
            echo "Error: Cannot resolve github.com even with Google DNS"
            return 1
        fi
    fi
    
    # Test HTTP connectivity
    if command -v curl >/dev/null 2>&1; then
        if ! curl -s --connect-timeout 10 https://github.com >/dev/null; then
            echo "Error: Cannot connect to GitHub via HTTPS"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget --timeout=10 --tries=1 -q --spider https://github.com; then
            echo "Error: Cannot connect to GitHub via HTTPS"
            return 1
        fi
    fi
    
    echo "Network connectivity check passed"
    return 0
}

# Function to retry git operations
retry_git_operation() {
    local max_attempts=3
    local attempt=1
    local cmd="$@"
    
    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt of $max_attempts: $cmd"
        if eval "$cmd"; then
            return 0
        fi
        
        echo "Attempt $attempt failed. Waiting 5 seconds before retry..."
        sleep 5
        ((attempt++))
    done
    
    echo "All $max_attempts attempts failed for: $cmd"
    return 1
}

# Load environment variables from .env file
if [ -f .env ]; then
    source .env
else
    echo "Warning: .env file not found. Using default values."
fi

# Comprehensive network connectivity check
echo "Performing comprehensive network connectivity check..."

# Check if we can resolve DNS
echo "Testing DNS resolution..."
if ! nslookup github.com >/dev/null 2>&1; then
    echo "Warning: DNS resolution for github.com failed"
    echo "Checking if we can reach DNS servers..."
    
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        echo "Can reach 8.8.8.8, DNS server is accessible"
    else
        echo "Cannot reach DNS servers, network connectivity issue detected"
    fi
else
    echo "✓ DNS resolution working correctly"
fi

# Check basic internet connectivity
echo "Testing internet connectivity..."
if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
    echo "✓ Internet connectivity confirmed"
else
    echo "✗ Internet connectivity failed"
    echo "This may cause issues with downloading documentation"
fi

# Check GitHub specifically
echo "Testing GitHub connectivity..."
if curl -s --connect-timeout 10 --max-time 30 --head "https://github.com" >/dev/null 2>&1; then
    echo "✓ GitHub is accessible via HTTPS"
elif curl -s --connect-timeout 10 --max-time 30 --head "https://20.200.245.247" >/dev/null 2>&1; then
    echo "✓ GitHub is accessible via IP address"
    echo "Note: Using IP address fallback due to DNS issues"
else
    echo "✗ GitHub is not accessible"
    echo "This will cause documentation download to fail"
fi

echo "Network connectivity check completed."
echo ""

# Check if ODOO_VERSIONS is set
if [ -z "$ODOO_VERSIONS" ]; then
    echo "Error: ODOO_VERSIONS not set in .env file"
    exit 1
fi

# Check network connectivity before proceeding
if ! check_network; then
    echo "Network connectivity check failed. Attempting DNS fix..."
    
    # Multiple DNS fix strategies for Docker containers
    echo "Applying DNS fixes for Docker environment..."
    
    # Strategy 1: Add GitHub IPs to /etc/hosts
    echo "Adding GitHub IPs to /etc/hosts..."
    if [ -w /etc/hosts ]; then
        if ! grep -q "github.com" /etc/hosts; then
            echo "20.200.245.247 github.com" >> /etc/hosts
            echo "140.82.112.4 github.com" >> /etc/hosts  # Alternative GitHub IP
            echo "140.82.113.4 github.com" >> /etc/hosts  # Another GitHub IP
        fi
    else
        echo "Warning: Cannot write to /etc/hosts, trying alternative methods..."
    fi
    
    # Strategy 2: Configure git to use specific DNS
    echo "Configuring git with alternative DNS settings..."
    git config --global http.proxy ""
    git config --global https.proxy ""
    
    # Strategy 3: Set environment variables for DNS
    export RESOLV_CONF="/etc/resolv.conf"
    
    # Test again after DNS fix
    if ! check_network; then
        echo "Standard DNS fix failed. Trying direct IP access..."
        
        # Strategy 4: Test direct IP access
        if curl -s --connect-timeout 10 --head "https://20.200.245.247" >/dev/null 2>&1; then
            echo "Direct IP access works. Configuring git to use IP..."
            # This will be handled in the repository access test
        else
            echo "Error: Network connectivity still failed after all DNS fixes."
            echo "This may indicate a network configuration issue in the Docker container."
            echo "Please check Docker network settings and DNS configuration."
            exit 1
        fi
    else
        echo "DNS fix successful. Proceeding with documentation download."
    fi
fi

# Define the repository with fallback options
REPO_URL="https://github.com/odoo/documentation.git"
REPO_URL_FALLBACK="https://20.200.245.247/odoo/documentation.git"  # GitHub IP fallback
REMOTE_NAME="odoo-docs"
BASE_DIR="raw_data/versions"

# Function to test repository access
test_repo_access() {
    local url="$1"
    echo "Testing access to: $url"
    
    if command -v curl >/dev/null 2>&1; then
        if curl -s --connect-timeout 10 --head "$url" >/dev/null 2>&1; then
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget --timeout=10 --tries=1 -q --spider "$url" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Determine which repository URL to use
if test_repo_access "$REPO_URL"; then
    echo "Using primary GitHub URL: $REPO_URL"
    FINAL_REPO_URL="$REPO_URL"
elif test_repo_access "$REPO_URL_FALLBACK"; then
    echo "Primary URL failed, using IP fallback: $REPO_URL_FALLBACK"
    FINAL_REPO_URL="$REPO_URL_FALLBACK"
    # Add GitHub IP to /etc/hosts for git operations
    echo "20.200.245.247 github.com" >> /etc/hosts
else
    echo "Error: Cannot access GitHub repository via any method"
    echo "Tried:"
    echo "  - $REPO_URL"
    echo "  - $REPO_URL_FALLBACK"
    exit 1
fi

# Initialize the main repository directory if it doesn't exist
mkdir -p $BASE_DIR

# Navigate to the base directory
cd $BASE_DIR || exit 1

# Convert comma-separated versions to array
IFS=',' read -ra VERSIONS <<< "$ODOO_VERSIONS"

# Loop through each version
for VERSION in "${VERSIONS[@]}"; do
    # Trim whitespace from version
    VERSION=$(echo "$VERSION" | tr -d '[:space:]')
    echo "Processing version $VERSION..."

    # Check if the version directory exists and contains a git repository
    if [ -d "$VERSION/.git" ]; then
        echo "Repository for version $VERSION already exists. Updating..."
        cd $VERSION || exit 1
        
        # Just fetch and pull the specific branch with retry
        if retry_git_operation "git fetch $REMOTE_NAME $VERSION" && \
           retry_git_operation "git merge $REMOTE_NAME/$VERSION --ff-only"; then
            echo "Successfully updated version $VERSION"
        else
            echo "Warning: Failed to update version $VERSION. Continuing with existing data."
        fi
        
        cd .. || exit 1
    else
        echo "Setting up new repository for version $VERSION..."
        
        # Create a directory for the version
        mkdir -p $VERSION
        cd $VERSION || exit 1

        # Initialize a git repository
        git init

        # Add the remote repository with retry
        if ! retry_git_operation "git remote add $REMOTE_NAME $FINAL_REPO_URL"; then
            echo "Error: Failed to add remote repository for version $VERSION"
            cd .. || exit 1
            continue
        fi

        # Enable sparse checkout
        git sparse-checkout init

        # Configure sparse checkout to be more specific
        echo "content/**" > .git/info/sparse-checkout

        # Fetch and checkout the specific branch with retry
        if retry_git_operation "git fetch $REMOTE_NAME $VERSION" && \
           retry_git_operation "git checkout -b $VERSION $REMOTE_NAME/$VERSION"; then
            echo "Version $VERSION setup complete."
        else
            echo "Error: Failed to setup version $VERSION. Skipping this version."
            cd .. || exit 1
            rm -rf $VERSION
            continue
        fi
        
        cd .. || exit 1
    fi
done

echo "All versions processed."

# Verify that data was actually pulled
echo "Verifying pulled data..."
success_count=0
total_count=0

for VERSION in $ODOO_VERSIONS; do
    total_count=$((total_count + 1))
    
    if [ -d "$VERSION/content" ] && [ "$(find "$VERSION/content" -type f -name "*.rst" | wc -l)" -gt 0 ]; then
        echo "✓ Version $VERSION: Data successfully pulled ($(find "$VERSION/content" -type f -name "*.rst" | wc -l) RST files)"
        success_count=$((success_count + 1))
    else
        echo "✗ Version $VERSION: No data found or empty content directory"
    fi
done

echo ""
echo "Summary: $success_count/$total_count versions successfully pulled"

if [ $success_count -eq 0 ]; then
    echo "Error: No data was successfully pulled for any version!"
    echo "This may indicate network connectivity issues or repository access problems."
    exit 1
elif [ $success_count -lt $total_count ]; then
    echo "Warning: Some versions failed to download. The RAG agent may have incomplete documentation."
    exit 2
else
    echo "Success: All versions downloaded successfully."
fi