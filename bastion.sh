#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Function for success message
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function for error message
fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    exit 1
}

# Function for normal message
info() {
    echo "[INFO] $1"
}

# Check if running as root
info "Checking root privileges..."
if [[ $EUID -ne 0 ]]; then
    fail "This script must be run as root. Use: sudo $0"
fi

# Check Amazon Linux
info "Checking OS..."
if [[ ! -f /etc/os-release ]]; then
    fail "Cannot detect OS"
fi

source /etc/os-release
if [[ "$ID" != "amzn" ]]; then
    info "Detected OS: $ID"
    read -p "This script is for Amazon Linux. Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    info "Amazon Linux detected"
fi

# Step 1: Clean yum cache
info "Cleaning yum cache..."
yum clean all
yum makecache

# Step 2: Install only essential packages (avoiding curl conflicts)
info "Installing essential packages..."
yum install -y wget net-tools iptables-services
if [ $? -eq 0 ]; then
    success "Essential packages installed successfully"
else
    # Try with --allowerasing if conflict occurs
    info "Trying with conflict resolution..."
    yum install -y wget net-tools iptables-services --allowerasing
    if [ $? -eq 0 ]; then
        success "Packages installed with conflict resolution"
    else
        fail "Failed to install essential packages"
    fi
fi

# Step 3: Download OpenVPN Access Server
info "Downloading OpenVPN Access Server..."
DOWNLOAD_URL="https://openvpn.net/downloads/openvpn-as-latest-amzn2.x86_64.rpm"

# Try multiple methods to download
if command -v wget &> /dev/null; then
    wget -O /tmp/openvpn-as.rpm "$DOWNLOAD_URL"
elif command -v curl &> /dev/null; then
    curl -L -o /tmp/openvpn-as.rpm "$DOWNLOAD_URL"
else
    # Install curl-minimal if no download tool available
    yum install -y curl-minimal
    curl -L -o /tmp/openvpn-as.rpm "$DOWNLOAD_URL"
fi

if [ -f /tmp/openvpn-as.rpm ] && [ -s /tmp/openvpn-as.rpm ]; then
    success "OpenVPN AS downloaded successfully"
else
    fail "Failed to download OpenVPN AS"
fi

# Step 4: Install OpenVPN Access Server
info "Installing OpenVPN Access Server..."
yum install -y /tmp/openvpn-as.rpm
if [ $? -eq 0 ]; then
    success "OpenVPN AS installed successfully"
else
    # Try with dependency resolution
    info "Trying with dependency resolution..."
    yum install -y /tmp/openvpn-as.rpm --allowerasing
    if [ $? -eq 0 ]; then
        success "OpenVPN AS installed with dependency resolution"
    else
        fail "Failed to install OpenVPN AS"
    fi
fi

# Step 5: Configure firewall
info "Configuring firewall..."
systemctl start iptables 2>/dev/null || true
systemctl enable iptables 2>/dev/null || true

# Save current iptables rules
iptables-save > /etc/sysconfig/iptables.backup

# Add OpenVPN ports
iptables -A INPUT -p tcp --dport 943 -j ACCEPT
iptables -A INPUT -p udp --dport 1194 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 945 -j ACCEPT

# Save iptables rules
iptables-save > /etc/sysconfig/iptables
if [ $? -eq 0 ]; then
    success "Firewall configured successfully"
else
    info "Firewall configuration completed with warnings"
fi

# Step 6: Start OpenVPN AS
info "Starting OpenVPN Access Server..."
systemctl start openvpnas
systemctl enable openvpnas

# Check if service is running
sleep 3
if systemctl is-active --quiet openvpnas; then
    success "OpenVPN AS service started successfully"
else
    info "Waiting a bit more for service to start..."
    sleep 10
    if systemctl is-active --quiet openvpnas; then
        success "OpenVPN AS service started successfully"
    else
        info "Service status: $(systemctl status openvpnas --no-pager | grep Active)"
        info "Proceeding with installation..."
    fi
fi

# Step 7: Display installation summary
echo ""
echo "=============================================="
success "OpenVPN Access Server INSTALLATION COMPLETE"
echo "=============================================="
info "Next steps:"
echo ""
echo "1. Wait 2-3 minutes for service to fully initialize"
echo ""
echo "2. Create configuration script:"
echo "   nano /root/configure_vpn.sh"
echo ""
echo "3. Run configuration script (after service is ready):"
echo "   sudo bash /root/configure_vpn.sh"
echo ""
echo "4. Access admin panel at:"
SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "YOUR_SERVER_IP")
echo "   https://${SERVER_IP}:943/admin"
echo ""
echo "=============================================="
info "Installation completed at: $(date)"

# Create minimal configuration script template
info "Creating configuration script template..."
cat > /root/configure_vpn.sh << 'EOF'
#!/bin/bash
# OpenVPN Configuration Script
# Run this after installation is complete (wait 2-3 minutes)

echo "Starting OpenVPN configuration..."
echo "Make sure the service is fully started before running this script."

# Wait for UI to be ready
echo "Checking if OpenVPN AS is ready..."
for i in {1..30}; do
    if curl -ks https://127.0.0.1:943/ >/dev/null 2>&1; then
        echo "OpenVPN AS is ready!"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 5
done

SCRIPTS="/usr/local/openvpn_as/scripts"

# Basic configuration
echo "Configuring OpenVPN..."
$SCRIPTS/sacli --key 'eula_accepted' --value 'true' ConfigPut
$SCRIPTS/sacli --user "admin" --new_pass "Openvpn@123" SetLocalPassword
$SCRIPTS/sacli --user "admin" --key 'prop_superuser' --value 'true' UserPropPut

echo "Configuration applied. Restarting service..."
systemctl restart openvpnas

echo "=============================================="
echo "OpenVPN Configuration Complete!"
echo "Admin URL: https://$(hostname -I | awk '{print $1}'):943/admin"
echo "Username: admin"
echo "Password: Openvpn@123"
echo "=============================================="
EOF

chmod +x /root/configure_vpn.sh
success "Configuration script template created: /root/configure_vpn.sh"