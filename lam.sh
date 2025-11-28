#!/bin/bash

###
# Script de instalación y configuración de LDAP Account Manager (LAM)
# Funciona en cualquier servidor sin necesidad de fijar la IP manualmente.
# BASE_DN: dc=amsa,dc=udl,dc=cat
###

BASE_DN="dc=amsa,dc=udl,dc=cat"
ADMIN_DN="cn=admin,${BASE_DN}"

# Detectar IP automáticamente
SERVER_IP=$(hostname -I | awk '{print $1}')
LDAP_SERVER="ldap://${SERVER_IP}:389"

LAM_CONF_DIR="/etc/lam"
LAM_CONF_FILE="${LAM_CONF_DIR}/config.cfg"

echo "[+] Instalando LDAP Account Manager..."
sudo dnf install -y lam httpd

echo "[+] Activando Apache..."
sudo systemctl enable httpd --now

echo "[+] Configurando LAM..."
sudo mkdir -p "$LAM_CONF_DIR"

cat <<EOF | sudo tee "$LAM_CONF_FILE" >/dev/null
# LAM configuración principal
defaultProfile: default

# Configuración del servidor LDAP
ServerURL: ${LDAP_SERVER}
Admins: ${ADMIN_DN}

# Sufijo base LDAP
treesuffix: ${BASE_DN}

# Hash de contraseñas
passwordDefaultHash: SSHA
> EOF

echo "[+] Ajustando permisos..."
sudo chown -R apache:apache "$LAM_CONF_DIR"
sudo chmod -R 750 "$LAM_CONF_DIR"

echo "[+] Abriendo HTTP en firewall..."
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --reload

echo ""
echo "=================================================="
echo "   LDAP ACCOUNT MANAGER INSTALADO Y CONFIGURADO"
echo "=================================================="
echo "URL de acceso:"
echo "  👉 http://${SERVER_IP}/lam"
echo ""
echo "Administrador LDAP:"
echo "  ${ADMIN_DN}"
echo ""
echo "Archivo de configuración:"
echo "  ${LAM_CONF_FILE}"
echo ""
echo "=================================================="
