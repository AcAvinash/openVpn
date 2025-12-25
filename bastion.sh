#!/bin/bash
set -euxo pipefail

############################################
# LOGGING
############################################
LOG_FILE="/var/log/openvpn-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

############################################
# VARIABLES
############################################
OPENVPN_AS_DIR="/usr/local/openvpn_as"
SCRIPTS="/usr/local/openvpn_as/scripts"

############################################
# STEP 1: OS CHECK (Amazon Linux 2023)
############################################
if [ -f /etc/os-release ]; then
  . /etc/os-release
  echo "Detected OS: $PRETTY_NAME"
else
  echo "OS detection failed"
  exit 1
fi

############################################
# STEP 2: SYSTEM UPDATE & REQUIRED PACKAGES
############################################
echo "=== STEP 2: Installing required packages ==="

dnf update -y
dnf install -y wget net-tools iproute

echo "STEP 2 completed"

############################################
# STEP 3: ADD OPENVPN OFFICIAL REPO
############################################
echo "=== STEP 3: Adding OpenVPN Access Server repository ==="

cat <<EOF >/etc/yum.repos.d/openvpn-as.repo
[openvpn-as]
name=OpenVPN Access Server
baseurl=https://as-repository.openvpn.net/as/alma/9/
enabled=1
gpgcheck=1
gpgkey=https://as-repository.openvpn.net/as-repo-public.gpg
EOF

echo "OpenVPN repo added successfully"

############################################
# STEP 4: INSTALL OPENVPN ACCESS SERVER
############################################
echo "=== STEP 4: Installing OpenVPN Access Server ==="

dnf install -y openvpn-as

echo "OpenVPN Access Server installation completed"

############################################
# STEP 5: SERVICE STATUS CHECK
############################################
echo "=== STEP 5: Checking OpenVPN service ==="

systemctl enable openvpnas
systemctl start openvpnas
systemctl status openvpnas --no-pager

############################################
# FINAL
############################################
echo "=========================================="
echo " OpenVPN Access Server INSTALL DONE "
echo " Admin URL : https://<PUBLIC-IP>:943/admin "
echo " User  URL : https://<PUBLIC-IP>:943/ "
echo "=========================================="
