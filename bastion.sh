#!/bin/bash
set -euxo pipefail

############################################
# COLORS
############################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

############################################
# LOGGING
############################################
LOG_FILE="/var/log/openvpn-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

############################################
# VARIABLES
############################################
INSTALL_DIR="/usr/local/src"
OPENVPN_AS_DIR="/usr/local/openvpn_as"
SCRIPTS="/usr/local/openvpn_as/scripts"

############################################
# STEP 1: OS CHECK
############################################
echo -e "${BLUE}=== STEP 1: OS Detection ===${NC}"

if [ -f /etc/os-release ]; then
  . /etc/os-release
  echo -e "${GREEN}✔ Detected OS: $PRETTY_NAME${NC}"
else
  echo -e "${RED}✘ OS detection failed${NC}"
  exit 1
fi

############################################
# STEP 2: SYSTEM UPDATE & PACKAGES
############################################
echo -e "${BLUE}=== STEP 2: Installing required packages ===${NC}"

dnf update -y
dnf install -y wget tar net-tools iproute

echo -e "${GREEN}✔ STEP 2 completed${NC}"

############################################
# STEP 3: DOWNLOAD OPENVPN ACCESS SERVER
############################################
echo -e "${BLUE}=== STEP 3: Downloading OpenVPN Access Server ===${NC}"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [ ! -f openvpn-as-latest.tar.gz ]; then
  echo -e "${YELLOW}⬇ Downloading OpenVPN Access Server...${NC}"
  wget https://openvpn.net/downloads/openvpn-as-latest.tar.gz
  echo -e "${GREEN}✔ Download completed${NC}"
else
  echo -e "${GREEN}✔ OpenVPN tarball already exists (skipping)${NC}"
fi

############################################
# STEP 4: EXTRACT TARBALL
############################################
echo -e "${BLUE}=== STEP 4: Extracting OpenVPN tarball ===${NC}"

tar -xzf openvpn-as-latest.tar.gz
cd openvpn_as*

echo -e "${GREEN}✔ Extraction completed${NC}"

############################################
# STEP 5: INSTALL OPENVPN ACCESS SERVER
############################################
echo -e "${BLUE}=== STEP 5: Installing OpenVPN Access Server ===${NC}"

./asinstall.sh --yes

echo -e "${GREEN}✔ Installation completed${NC}"

############################################
# STEP 6: SERVICE STATUS CHECK
############################################
echo -e "${BLUE}=== STEP 6: Checking OpenVPN service ===${NC}"

systemctl enable openvpnas
systemctl status openvpnas --no-pager

############################################
# FINAL
############################################
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN} OpenVPN Access Server INSTALL DONE ${NC}"
echo -e "${YELLOW} Admin URL : https://<PUBLIC-IP>:943/admin ${NC}"
echo -e "${YELLOW} User  URL : https://<PUBLIC-IP>:943/ ${NC}"
echo -e "${GREEN}==========================================${NC}"
