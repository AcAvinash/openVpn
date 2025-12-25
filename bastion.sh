#!/bin/bash
# OpenVPN + optional Unbound installer for Amazon Linux 2023 with colored output
# Tested on AL2023

set -euo pipefail

# Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"

info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Root check
if [ "$EUID" -ne 0 ]; then
    error "Run as root!"
    exit 1
fi

# TUN/TAP check
if [ ! -c /dev/net/tun ]; then
    error "TUN device not available!"
    exit 1
fi

info "Installing dependencies..."
dnf install -y openvpn iptables openssl wget curl tar systemd-resolved
success "Dependencies installed."

# Ask for basic settings
read -rp "Public IP or hostname (auto-detect): " PUBLIC_IP
PUBLIC_IP=${PUBLIC_IP:-$(curl -s https://ip.seeip.org)}
read -rp "OpenVPN port [1194]: " PORT
PORT=${PORT:-1194}
read -rp "Protocol (udp/tcp) [udp]: " PROTOCOL
PROTOCOL=${PROTOCOL:-udp}
read -rp "Enable IPv6 support? (y/n) [n]: " IPV6
IPV6=${IPV6:-n}
read -rp "Use Unbound as DNS resolver? (y/n) [n]: " USE_UNBOUND
USE_UNBOUND=${USE_UNBOUND:-n}

# Optional Unbound install
if [[ $USE_UNBOUND == "y" ]]; then
    info "Installing Unbound DNS resolver..."
    dnf install -y unbound
    cat >/etc/unbound/unbound.conf <<EOF
server:
    interface: 10.8.0.1
    access-control: 10.8.0.0/24 allow
    hide-identity: yes
    hide-version: yes
    use-caps-for-id: yes
    prefetch: yes
EOF
    systemctl enable --now unbound
    success "Unbound installed and running."
fi

# Easy-RSA setup
info "Setting up Easy-RSA..."
EASYRSA_DIR="/etc/openvpn/easy-rsa"
mkdir -p "$EASYRSA_DIR"
cd /tmp
wget -O easy-rsa.tgz https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.2/EasyRSA-3.1.2.tgz
tar xzf easy-rsa.tgz --strip-components=1 -C "$EASYRSA_DIR"
rm -f easy-rsa.tgz
cd "$EASYRSA_DIR"
./easyrsa init-pki
./easyrsa --batch build-ca nopass
SERVER_NAME="server_$(head /dev/urandom | tr -dc a-z0-9 | head -c8)"
./easyrsa build-server-full "$SERVER_NAME" nopass
openssl dhparam -out dh.pem 2048
openvpn --genkey --secret tls-crypt.key
success "Certificates and keys generated."

# Move certs
cp pki/ca.crt pki/private/ca.key "pki/issued/$SERVER_NAME.crt" "pki/private/$SERVER_NAME.key" dh.pem tls-crypt.key /etc/openvpn

# Create server.conf
info "Creating server.conf..."
cat >/etc/openvpn/server.conf <<EOF
port $PORT
proto $PROTOCOL
dev tun
user nobody
group nobody
persist-key
persist-tun
keepalive 10 120
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "dhcp-option DNS 10.8.0.1"
push "redirect-gateway def1 bypass-dhcp"
tls-crypt tls-crypt.key
crl-verify crl.pem
ca ca.crt
cert $SERVER_NAME.crt
key $SERVER_NAME.key
dh dh.pem
auth SHA256
cipher AES-128-GCM
ncp-ciphers AES-128-GCM
tls-server
tls-version-min 1.2
status /var/log/openvpn/status.log
verb 3
EOF

# IPv6
if [[ $IPV6 == "y" ]]; then
    echo 'server-ipv6 fd42:42:42:42::/112
tun-ipv6
push tun-ipv6
push "route-ipv6 2000::/3"
push "redirect-gateway ipv6"' >>/etc/openvpn/server.conf
fi

# Enable IP forwarding
info "Enabling IP forwarding..."
echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/99-openvpn.conf
[[ $IPV6 == "y" ]] && echo 'net.ipv6.conf.all.forwarding=1' >>/etc/sysctl.d/99-openvpn.conf
sysctl --system
success "IP forwarding enabled."

# Enable and start OpenVPN
info "Starting OpenVPN service..."
systemctl enable --now openvpn-server@server.service
success "OpenVPN service started and enabled at boot."

success "OpenVPN installation complete!"
echo -e "${GREEN}Server name:${NC} $SERVER_NAME"
echo -e "${GREEN}Connect using port:${NC} $PORT/$PROTOCOL"


