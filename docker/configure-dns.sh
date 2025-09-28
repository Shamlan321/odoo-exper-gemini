#!/bin/bash

# DNS Configuration Script for Docker Container
# This script ensures proper DNS resolution for GitHub and other external services

echo "Configuring DNS for Docker container..."

# Function to test DNS resolution
test_dns() {
    local hostname="$1"
    echo "Testing DNS resolution for $hostname..."
    
    if nslookup "$hostname" >/dev/null 2>&1; then
        echo "✓ DNS resolution for $hostname: SUCCESS"
        return 0
    else
        echo "✗ DNS resolution for $hostname: FAILED"
        return 1
    fi
}

# Function to test network connectivity
test_connectivity() {
    local host="$1"
    echo "Testing connectivity to $host..."
    
    if ping -c 1 -W 5 "$host" >/dev/null 2>&1; then
        echo "✓ Connectivity to $host: SUCCESS"
        return 0
    else
        echo "✗ Connectivity to $host: FAILED"
        return 1
    fi
}

# Backup original resolv.conf
if [ -f /etc/resolv.conf ] && [ ! -f /etc/resolv.conf.backup ]; then
    cp /etc/resolv.conf /etc/resolv.conf.backup
    echo "Backed up original resolv.conf"
fi

# Configure DNS servers
echo "Configuring DNS servers..."
cat > /etc/resolv.conf << EOF
# DNS configuration for Docker container
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
nameserver 1.0.0.1

# Search domains
search localdomain

# Options
options timeout:5
options attempts:3
options rotate
options single-request-reopen
EOF

echo "DNS configuration updated."

# Test DNS resolution
echo ""
echo "Testing DNS resolution..."
dns_success=0

for host in "github.com" "google.com" "cloudflare.com"; do
    if test_dns "$host"; then
        dns_success=1
    fi
done

if [ $dns_success -eq 0 ]; then
    echo "Warning: DNS resolution failed for all test hosts"
    echo "Adding static entries to /etc/hosts as fallback..."
    
    # Add static entries for critical services
    cat >> /etc/hosts << EOF

# Static DNS entries for critical services
20.200.245.247 github.com
140.82.112.4 github.com
140.82.113.4 github.com
8.8.8.8 dns.google
1.1.1.1 cloudflare-dns.com
EOF
    
    echo "Static DNS entries added to /etc/hosts"
fi

# Test connectivity
echo ""
echo "Testing network connectivity..."
connectivity_success=0

for host in "8.8.8.8" "1.1.1.1"; do
    if test_connectivity "$host"; then
        connectivity_success=1
        break
    fi
done

if [ $connectivity_success -eq 0 ]; then
    echo "Warning: Network connectivity test failed"
    echo "This may indicate network configuration issues"
else
    echo "✓ Network connectivity confirmed"
fi

# Configure Git for better network handling
echo ""
echo "Configuring Git for better network handling..."
git config --global http.postBuffer 524288000
git config --global http.maxRequestBuffer 100M
git config --global core.compression 0
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999
git config --global http.sslVerify true

echo "Git configuration updated."

# Final test
echo ""
echo "Final connectivity test to GitHub..."
if curl -s --connect-timeout 10 --max-time 30 --head "https://github.com" >/dev/null 2>&1; then
    echo "✓ GitHub connectivity: SUCCESS"
    echo "DNS configuration completed successfully."
    exit 0
else
    echo "✗ GitHub connectivity: FAILED"
    echo "DNS configuration completed with warnings."
    echo "The application may experience connectivity issues."
    exit 1
fi