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
    php-gd php-gmp php-zip \
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
#  CONFIGURAR LAM
# ========================

# Configurar config.cfg primero
cat > /var/lib/ldap-account-manager/config/config.cfg << 'EOF'
password: {SSHA}4C6O8OuyVYk8YNjDSpF5gLZkbxI= u89Ej5wT
ServerURL: ldap://$LDAP_SERVER:389
Passwd: lam
Admins: cn=admin,$BASE_DN
treesuffix: $BASE_DN

types: suffix_user: ou=users,$BASE_DN
types: suffix_group: ou=groups,$BASE_DN
modules: posixAccount_minUID: 1000
modules: posixAccount_maxUID: 30000
modules: posixGroup_minGID: 10000
modules: posixGroup_maxGID: 20000
EOF

# Crear directorio de perfiles
mkdir -p /var/lib/ldap-account-manager/config/profiles

# Configurar perfil default.conf con hash de contraseña
cat > /var/lib/ldap-account-manager/config/profiles/default.conf << EOF
# LAM configuration

# server address (e.g. ldap://localhost:389 or ldaps://localhost:636)
ServerURL: ldap://$LDAP_SERVER:389

# list of users who are allowed to use LDAP Account Manager
# names have to be separated by semicolons
# e.g. admins: cn=admin,dc=yourdomain,dc=org;cn=root,dc=yourdomain,dc=org
Admins: cn=admin,$BASE_DN

# password to change these preferences via webfrontend (default: lam)
Passwd: {SSHA}gVzc3vDbzU4TXMhtjlXaEKJGOvK3f82i

# suffix of tree view
treesuffix: $BASE_DN

# default language (a line from config/language)
defaultLanguage: es_ES.utf8:UTF-8:Spanish (España)

# LDAP search limit
searchLimit: 0

# type settings
types: suffix_user: ou=users,$BASE_DN
types: suffix_group: ou=groups,$BASE_DN

# module settings
modules: posixAccount_minUID: 1000
modules: posixAccount_maxUID: 30000
modules: posixGroup_minGID: 10000
modules: posixGroup_maxGID: 20000
EOF

# Permisos correctos
chown -R apache:apache /var/lib/ldap-account-manager
chmod 600 /var/lib/ldap-account-manager/config/config.cfg
chmod 600 /var/lib/ldap-account-manager/config/profiles/default.conf

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
