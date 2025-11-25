#!/bin/bash
set -ex  # Muestra cada comando y detiene al fallar

# Validar IP del servidor LDAP
if [ -z "$1" ]; then
    echo "Error: Proporciona IP del servidor LDAP"
    exit 1
fi

LDAP_SERVER=$1
BASE_DN="dc=amsa,dc=udl,dc=cat"
ADMIN_DN="cn=admin,$BASE_DN"

echo "=== INICIANDO INSTALACIÓN DE LAM EN AL2023 (httpd24) ==="

# Esperar servidor LDAP
echo "Esperando servidor LDAP..."
until nc -z $LDAP_SERVER 389; do
    echo "Servidor LDAP no disponible, esperando 10s..."
    sleep 10
done

# Actualizar sistema
dnf update -y

# Habilitar EPEL
dnf install -y epel-release
dnf config-manager --set-enabled epel

# Instalar Apache y PHP
dnf module enable -y php:8.2
dnf install -y httpd24 php php-ldap php-mbstring wget unzip

# Descargar e instalar LAM manualmente (última versión estable)
cd /tmp
wget https://sourceforge.net/projects/ldap-account-manager/files/latest/download -O lam.zip
unzip lam.zip -d /var/www/html/
mv /var/www/html/lam-* /var/www/html/lam
chown -R apache:apache /var/www/html/lam

# Crear config.cfg
cat > /var/www/html/lam/config.cfg << EOF
<?php
const CONFIG_SERVER_URL = 'http://localhost/lam';
const CONFIG_CIPHER = 'blowfish';
const CONFIG_PASSWORD_MIN_LENGTH = '6';
const CONFIG_MASTER_PASSWORD = 'lam';
const CONFIG_LDAP_URL = 'ldap://$LDAP_SERVER:389';
const CONFIG_LDAP_SUFFIX = '$BASE_DN';
const CONFIG_LDAP_BIND_USER = '$ADMIN_DN';
const CONFIG_LDAP_BIND_PASS = 'lam';
const CONFIG_USER_MODULE = 'inetOrgPerson';
const CONFIG_GROUP_MODULE = 'posixGroup';
?>
EOF

chown apache:apache /var/www/html/lam/config.cfg
chmod 640 /var/www/html/lam/config.cfg

# Iniciar y habilitar Apache
systemctl enable httpd24-httpd
systemctl start httpd24-httpd

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
</head>
<body>
    <h1>LDAP Account Manager</h1>
    <p><a href="/lam">Acceder a LAM</a></p>
    <p>Usuario: cn=admin,dc=amsa,dc=udl,dc=cat</p>
    <p>Contraseña: lam</p>
</body>
</html>
EOF

echo "=== LAM INSTALADO CORRECTAMENTE ==="
echo "URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/lam"
