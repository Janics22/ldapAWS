#!/bin/bash
set -e

# Validar IP del servidor LDAP
if [ -z "$1" ]; then
    echo "Error: Proporciona IP del servidor LDAP"
    exit 1
fi

LDAP_SERVER=$1
BASE_DN="dc=amsa,dc=udl,dc=cat"
ADMIN_DN="cn=admin,$BASE_DN"
LAM_VERSION="8.7"

echo "=== INICIANDO INSTALACIÓN DE LAM EN AL2023 ==="

# Esperar servidor LDAP
echo "Esperando servidor LDAP..."
until nc -z $LDAP_SERVER 389; do
    echo "Servidor LDAP no disponible, esperando 10s..."
    sleep 10
done

# Actualizar sistema
dnf update -y

# Instalar Apache y PHP con extensiones necesarias
dnf install -y httpd php php-ldap php-mbstring php-xml php-json wget tar

# Descargar e instalar LAM desde código fuente
cd /tmp
wget https://github.com/LDAPAccountManager/lam/releases/download/${LAM_VERSION}/ldap-account-manager-${LAM_VERSION}.tar.bz2
tar -xjf ldap-account-manager-${LAM_VERSION}.tar.bz2
mv ldap-account-manager-${LAM_VERSION} /var/www/html/lam
chown -R apache:apache /var/www/html/lam

# Crear directorios de configuración
mkdir -p /var/lib/ldap-account-manager/config
mkdir -p /var/lib/ldap-account-manager/sess
mkdir -p /var/lib/ldap-account-manager/tmp
chown -R apache:apache /var/lib/ldap-account-manager
chmod 700 /var/lib/ldap-account-manager/config

# Configurar LAM
cat > /var/lib/ldap-account-manager/config/lam.conf << EOF
# Server address
ServerURL: ldap://$LDAP_SERVER:389
Activate TLS: no

# LDAP search settings
LDAPSuffix: $BASE_DN
defaultLanguage: en_GB.utf8:UTF-8:English (Great Britain)

# List of attributes to show in user list
userListAttributes: #uid;#givenName;#sn;#uidNumber;#gidNumber
groupListAttributes: #cn;#gidNumber;#memberUID;#description

# Password settings
minPasswordLength: 6
passwordMustNotContain3Chars: false
passwordMustNotContainUser: false

# Tree suffix for accounts
treesuffix: $BASE_DN
defaultLanguage: en_GB.utf8:UTF-8:English (Great Britain)

types: suffix_user: ou=users,$BASE_DN
types: suffix_group: ou=groups,$BASE_DN

# Access level
accessLevel: 100

# Login settings
admins: $ADMIN_DN
loginMethod: list
loginSearchSuffix: $BASE_DN

# Module settings
modules: posixAccount_minUID: 1000
modules: posixAccount_maxUID: 30000
modules: posixAccount_minMachine: 50000
modules: posixAccount_maxMachine: 60000
modules: posixGroup_minGID: 10000
modules: posixGroup_maxGID: 20000
modules: posixGroup_pwdHash: SSHA
EOF

# Configurar permisos
chown apache:apache /var/lib/ldap-account-manager/config/lam.conf
chmod 600 /var/lib/ldap-account-manager/config/lam.conf

# Configurar PHP para LAM
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

# Iniciar y habilitar Apache
systemctl enable httpd
systemctl start httpd

# Configurar firewall
systemctl enable firewalld
systemctl start firewalld
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# Crear página de inicio
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>LDAP Account Manager</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .info { background: #e7f3fe; border-left: 6px solid #2196F3; padding: 12px; margin: 10px 0; }
    </style>
</head>
<body>
    <h1>LDAP Account Manager</h1>
    <div class="info">
        <p><strong><a href="/lam">Acceder a LAM</a></strong></p>
        <p><strong>Credenciales de acceso:</strong></p>
        <ul>
            <li>Usuario: cn=admin,dc=amsa,dc=udl,dc=cat</li>
            <li>Contraseña: 1234</li>
        </ul>
        <p><strong>Master password (configuración):</strong> lam</p>
    </div>
</body>
</html>
EOF

echo "=== LAM INSTALADO CORRECTAMENTE ==="
echo "URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/lam"
echo "Usuario: $ADMIN_DN"
echo "Contraseña: 1234"
