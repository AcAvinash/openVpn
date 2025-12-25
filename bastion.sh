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

# Step 1: Update system
info "Updating system packages..."
yum update -y
if [ $? -eq 0 ]; then
    success "System updated successfully"
else
    fail "Failed to update system"
fi

# Step 2: Install dependencies
info "Installing dependencies..."
yum install -y wget curl net-tools iptables-services
if [ $? -eq 0 ]; then
    success "Dependencies installed successfully"
else
    fail "Failed to install dependencies"
fi

# Step 3: Download OpenVPN Access Server
info "Downloading OpenVPN Access Server..."
wget -O /tmp/openvpn-as.rpm https://openvpn.net/downloads/openvpn-as-latest-amzn2.x86_64.rpm
if [ $? -eq 0 ]; then
    success "Download completed successfully"
else
    fail "Failed to download OpenVPN AS"
fi

# Step 4: Install OpenVPN Access Server
info "Installing OpenVPN Access Server..."
yum install -y /tmp/openvpn-as.rpm
if [ $? -eq 0 ]; then
    success "OpenVPN AS installed successfully"
else
    fail "Failed to install OpenVPN AS"
fi

# Step 5: Configure firewall
info "Configuring firewall..."
systemctl start iptables
systemctl enable iptables

# Open necessary ports
iptables -A INPUT -p tcp --dport 943 -j ACCEPT
iptables -A INPUT -p udp --dport 1194 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 945 -j ACCEPT

# Save iptables rules
service iptables save
if [ $? -eq 0 ]; then
    success "Firewall configured successfully"
else
    fail "Failed to configure firewall"
fi

# Step 6: Start OpenVPN AS
info "Starting OpenVPN Access Server..."
systemctl start openvpnas
systemctl enable openvpnas

# Check if service is running
sleep 5
if systemctl is-active --quiet openvpnas; then
    success "OpenVPN AS service started successfully"
else
    fail "Failed to start OpenVPN AS service"
fi

# Step 7: Create configuration script
info "Creating configuration script..."

cat > /root/configure_openvpn_as.sh << 'EOF'
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    exit 1
}

info() {
    echo "[INFO] $1"
}

SCRIPTS="/usr/local/openvpn_as/scripts"
USERNAME="admin"
PASSWORD='Openvpn@123'   # Change this in production

info "Waiting for OpenVPN AS UI to be ready (may take 2-3 minutes)..."

# Wait for UI (maximum 5 minutes)
MAX_WAIT=300
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    if curl -ks https://127.0.0.1:943/ >/dev/null 2>&1; then
        success "OpenVPN AS UI is ready"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED+5))
    info "Waited $ELAPSED seconds..."
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    fail "OpenVPN AS UI did not start within 5 minutes"
fi

# 1. Accept EULA
info "Accepting EULA..."
$SCRIPTS/sacli --key 'eula_accepted' --value 'true' ConfigPut
if [ $? -eq 0 ]; then
    success "EULA accepted"
else
    fail "Failed to accept EULA"
fi

# 2. Set admin user and password
info "Setting admin credentials..."
$SCRIPTS/sacli --user "$USERNAME" --new_pass "$PASSWORD" SetLocalPassword
if [ $? -eq 0 ]; then
    success "Admin password set"
else
    fail "Failed to set admin password"
fi

$SCRIPTS/sacli --user "$USERNAME" --key 'prop_superuser' --value 'true' UserPropPut
if [ $? -eq 0 ]; then
    success "Admin privileges granted"
else
    fail "Failed to grant admin privileges"
fi

# 3. VPN port and protocol
info "Configuring VPN settings..."
$SCRIPTS/sacli --key 'vpn.server.port' --value '1194' ConfigPut
$SCRIPTS/sacli --key 'vpn.server.protocol' --value 'udp' ConfigPut
if [ $? -eq 0 ]; then
    success "VPN settings configured"
else
    fail "Failed to configure VPN settings"
fi

# 4. DNS configuration
info "Configuring DNS..."
$SCRIPTS/sacli --key 'vpn.client.dns.server_auto' --value 'true' ConfigPut
$SCRIPTS/sacli --key 'cs.prof.defaults.dns.0' --value '8.8.8.8' ConfigPut
$SCRIPTS/sacli --key 'cs.prof.defaults.dns.1' --value '1.1.1.1' ConfigPut
if [ $? -eq 0 ]; then
    success "DNS configured"
else
    fail "Failed to configure DNS"
fi

# 5. Route all client traffic through VPN
info "Configuring routing..."
$SCRIPTS/sacli --key 'vpn.client.routing.reroute_gw' --value 'true' ConfigPut
if [ $? -eq 0 ]; then
    success "Routing configured"
else
    fail "Failed to configure routing"
fi

# 6. Block access to VPN server services from clients
info "Configuring gateway access..."
$SCRIPTS/sacli --key 'vpn.server.routing.gateway_access' --value 'true' ConfigPut
if [ $? -eq 0 ]; then
    success "Gateway access configured"
else
    fail "Failed to configure gateway access"
fi

# 7. Save configuration
info "Saving configuration..."
$SCRIPTS/sacli ConfigSync
if [ $? -eq 0 ]; then
    success "Configuration saved"
else
    fail "Failed to save configuration"
fi

# 8. Restart service
info "Restarting OpenVPN AS..."
systemctl restart openvpnas
if [ $? -eq 0 ]; then
    success "Service restarted successfully"
else
    fail "Failed to restart service"
fi

info "Configuration completed!"
SERVER_IP=$(curl -s http://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')
echo "=============================================="
echo "Admin URL: https://${SERVER_IP}:943/admin"
echo "Username: $USERNAME"
echo "Password: $PASSWORD"
echo "=============================================="
info "IMPORTANT: Change the default password immediately!"
EOF

chmod +x /root/configure_openvpn_as.sh
success "Configuration script created: /root/configure_openvpn_as.sh"

# Step 8: Display installation summary
info "Installation Summary:"
echo "=============================================="
success "OpenVPN Access Server installed successfully"
info "Next steps:"
echo "1. Wait 2-3 minutes for service to fully start"
echo "2. Run configuration script:"
echo "   sudo /root/configure_openvpn_as.sh"
echo "3. Access admin panel at:"
SERVER_IP=$(curl -s http://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')
echo "   https://${SERVER_IP}:943/admin"
echo "=============================================="

info "Installation completed at: $(date)"