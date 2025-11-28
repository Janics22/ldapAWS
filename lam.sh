#!/bin/bash
set -e

# ========================
#  CONFIG
# ========================
if [ -z "$1" ]; then
    echo "Error: Falta la IP del servidor LDAP"
    exit 1
fi

LDAP_SERVER=$1
BASE_DN="dc=amsa,dc=udl,dc=cat"
ADMIN_DN="cn=admin,$BASE_DN"
LAM_VERSION="8.7"

echo "=== INICIANDO INSTALACIÓN DE LAM EN AMAZON LINUX 2023 ==="


# ========================
#  ESPERAR LDAP
# ========================
echo "Esperando servidor LDAP..."
until nc -z $LDAP_SERVER 389; do
    echo "LDAP no disponible, esperando 10s..."
    sleep 10
done


# ========================
#  SISTEMA + PHP + EXTENSIONES
# ========================
dnf update -y

dnf install -y \
    httpd \
    php php-cli php-common \
    php-ldap php-mbstring php-xml php-json php-pdo php-opcache \
    php-gd php-gmp \
    wget tar


# ========================
#  DESCARGAR LAM 8.7
# ========================
cd /tmp
wget https://github.com/LDAPAccountManager/lam/releases/download/${LAM_VERSION}/ldap-account-manager-${LAM_VERSION}.tar.bz2
tar -xjf ldap-account-manager-${LAM_VERSION}.tar.bz2

mv ldap-account-manager-${LAM_VERSION} /var/www/html/lam
chown -R apache:apache /var/www/html/lam


# ========================
#  DIRECTORIOS DE LAM
# ========================
mkdir -p /var/lib/ldap-account-manager/config
mkdir -p /var/lib/ldap-account-manager/sess
mkdir -p /var/lib/ldap-account-manager/tmp

chown -R apache:apache /var/lib/ldap-account-manager
chmod 700 /var/lib/ldap-account-manager/config


# ========================
#  COPIAR CONFIGURACIÓN BASE
# ========================
cp /var/www/html/lam/config/config.cfg_sample /var/lib/ldap-account-manager/config/config.cfg || true
cp /var/www/html/lam/config/lam.conf_sample /var/lib/ldap-account-manager/config/lam.conf || true


# ========================
#  CONFIGURAR LAM
# ========================
cat > /var/lib/ldap-account-manager/config/lam.conf << EOF
ServerURL: ldap://$LDAP_SERVER:389
Activate TLS: no

LDAPSuffix: $BASE_DN

admins: $ADMIN_DN
loginMethod: list
loginSearchSuffix: $BASE_DN

types: suffix_user: ou=users,$BASE_DN
types: suffix_group: ou=groups,$BASE_DN

modules: posixAccount_minUID: 1000
modules: posixAccount_maxUID: 30000

modules: posixGroup_minGID: 10000
modules: posixGroup_maxGID: 20000
EOF

chown apache:apache /var/lib/ldap-account-manager/config/lam.conf
chmod 600 /var/lib/ldap-account-manager/config/lam.conf


# ========================
#  CONFIGURAR APACHE
# ========================
cat > /etc/httpd/conf.d/lam.conf << EOF
Alias /lam /var/www/html/lam

<Directory /var/www/html/lam>
    Options FollowSymLinks
    AllowOverride All
    Require all granted

    <IfModule mod_php.c>
        php_value session.save_path /var/lib/ldap-account-manager/sess
        php_value include_path /var/www/html/lam:/var/www/html/lam/lib
    </IfModule>
</Directory>
EOF

systemctl enable httpd
systemctl start httpd


# ========================
#  PÁGINA DE INICIO
# ========================
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head><title>LDAP Account Manager</title></head>
<body>
<h1>LDAP Account Manager</h1>
<p><a href="/lam">Acceder a LAM</a></p>
<p>Usuario: cn=admin,$BASE_DN</p>
<p>Contraseña: 1234</p>
</body>
</html>
EOF


# ========================
#  INFO FINAL
# ========================
echo "=== LAM INSTALADO CORRECTAMENTE ==="
echo "URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/lam"
echo "Usuario: $ADMIN_DN"
echo "Contraseña: 1234"
