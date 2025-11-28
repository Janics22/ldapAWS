#!/bin/bash
set -e

#############################################
#   CONFIGURACIÓN INTEGRADA CON TUS SCRIPTS
#############################################

# Detectar automáticamente la IP pública de la instancia AWS
echo "[INFO] Detectando automáticamente la IP del servidor LDAP..."
LDAP_SERVER=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=ldap-server" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)
echo "[INFO] IP pública detectada: $LDAP_SERVER"

BASE_DN="dc=amsa,dc=udl,dc=cat"
ADMIN_DN="cn=admin,$BASE_DN"
ADMIN_PASS="1234"     # MISMO PASSWORD QUE server_ldap.sh
LAM_MASTER_PASS="lam"
LAM_VERSION="8.7"

echo "=== INSTALANDO LAM EN AMAZON LINUX 2023 ==="

#############################################
#   ESPERAR A QUE EL SERVIDOR LDAP ESTÉ LISTO
#############################################

echo "[INFO] Esperando a que LDAP responda en $LDAP_SERVER:389"

for i in {1..30}; do
    if nc -z "$LDAP_SERVER" 389; then
        echo "[INFO] LDAP está disponible."
        break
    fi
    echo "[WARN] Aún no responde, reintentando..."
    sleep 5
done

#############################################
#   INSTALAR DEPENDENCIAS
#############################################

dnf update -y
dnf install -y httpd php php-ldap php-mbstring php-gd php-gmp php-zip wget tar nc

#############################################
#   INSTALAR LAM MANUALMENTE (ZIP)
#############################################

cd /tmp
wget https://github.com/LDAPAccountManager/lam/releases/download/${LAM_VERSION}/ldap-account-manager-${LAM_VERSION}.tar.bz2
tar -xjf ldap-account-manager-${LAM_VERSION}.tar.bz2
rm -rf /var/www/html/lam
mv ldap-account-manager-${LAM_VERSION} /var/www/html/lam

#############################################
#   CONFIGURACIÓN DE LAM
#############################################

mkdir -p /var/lib/ldap-account-manager/config
mkdir -p /etc/ldap-account-manager

cat > /etc/ldap-account-manager/config.cfg <<EOF
<?php
const CONFIG_SERVER_URL = 'http://localhost/lam';
const CONFIG_CIPHER = 'blowfish';
const CONFIG_PASSWORD_MIN_LENGTH = '6';
const CONFIG_MASTER_PASSWORD = '$LAM_MASTER_PASS';
const CONFIG_LDAP_URL = 'ldap://$LDAP_SERVER:389';
const CONFIG_LDAP_SUFFIX = '$BASE_DN';
const CONFIG_LDAP_BIND_USER = '$ADMIN_DN';
const CONFIG_LDAP_BIND_PASS = '$ADMIN_PASS';
const CONFIG_USER_MODULE = 'inetOrgPerson';
const CONFIG_GROUP_MODULE = 'posixGroup';
?>
EOF

chown -R apache:apache /etc/ldap-account-manager
chown -R apache:apache /var/lib/ldap-account-manager
chown -R apache:apache /var/www/html/lam
chmod 640 /etc/ldap-account-manager/config.cfg

#############################################
#   CONFIGURAR APACHE
#############################################

systemctl enable httpd
systemctl start httpd

#############################################
#   FIREWALL (AL2023 NO TRAE firewalld)
#############################################

echo "[INFO] firewalld NO está disponible en Amazon Linux 2023, ignorado."

#############################################
#   CREAR PÁGINA DE INICIO
#############################################

cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>LDAP Account Manager</title>
</head>
<body>
    <h1>LDAP Account Manager</h1>
    <p><a href="/lam">Acceder a LAM</a></p>
    <p>Usuario administrador LDAP: <strong>$ADMIN_DN</strong></p>
    <p>Contraseña: <strong>$ADMIN_PASS</strong></p>
    <p>Master Password (LAM): <strong>$LAM_MASTER_PASS</strong></p>
</body>
</html>
EOF

#############################################

echo "=== LAM INSTALADO CORRECTAMENTE ==="
echo "URL: http://$LDAP_SERVER/lam"
echo "Usuario LDAP: $ADMIN_DN"
echo "Contraseña LDAP: $ADMIN_PASS"
