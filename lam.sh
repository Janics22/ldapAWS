#!/bin/bash
# lam.sh - Instalación robusta de LDAP Account Manager
set -e

if [ -z "$1" ]; then
    echo "Error: Debe proporcionar la IP del servidor LDAP"
    exit 1
fi

LDAP_SERVER=$1
BASE_DN="dc=amsa,dc=udl,dc=cat"
ADMIN_DN="cn=admin,$BASE_DN"

echo "=== INSTALANDO LDAP ACCOUNT MANAGER ==="
echo "Servidor LDAP: $LDAP_SERVER"

# Espera robusta para el servidor LDAP
echo "Esperando a que el servidor LDAP esté completamente listo..."

# Método 1: Esperar por el archivo de señal
for i in {1..30}; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ec2-user@$LDAP_SERVER "test -f /tmp/ldap_server_ready" 2>/dev/null; then
        echo "Servidor LDAP listo (señal detectada)"
        break
    fi
    echo "Intento $i/30 - Esperando señal del servidor LDAP..."
    sleep 30
done

# Método 2: Esperar por respuesta LDAP
for i in {1..20}; do
    if ldapsearch -x -H ldap://$LDAP_SERVER -b "$BASE_DN" -s base "(objectClass=*)" 2>/dev/null | grep -q "dn:"; then
        echo "LDAP respondiendo correctamente"
        break
    fi
    echo "Intento $i/20 - Esperando respuesta LDAP..."
    sleep 20
done

# Instalar Apache, PHP y dependencias (con reintentos)
echo "Instalando Apache, PHP y dependencias..."
for attempt in {1..3}; do
    dnf update -y && \
    dnf install -y httpd php php-ldap php-mbstring php-xml php-json php-gettext openssh-clients && break
    echo "Intento $attempt/3 falló, reintentando en 10 segundos..."
    sleep 10
done

# Instalar LAM desde repositorio EPEL
echo "Instalando LAM..."
for attempt in {1..3}; do
    dnf install -y epel-release && \
    dnf install -y ldap-account-manager && break
    echo "Intento $attempt/3 falló, reintentando en 10 segundos..."
    sleep 10
done

# Configurar Apache para LAM
echo "Configurando Apache..."
cp /etc/ldap-account-manager/config.cfg /etc/ldap-account-manager/config.cfg.backup 2>/dev/null || true

# Crear configuración LAM robusta
cat > /etc/ldap-account-manager/config.cfg << EOL
<?php
/*
 * Configuración LAM automática
 */

// Configuración de servidor
const CONFIG_SERVER_URL = 'http://\${_SERVER['HTTP_HOST']}/lam';

// Configuración de seguridad
const CONFIG_CIPHER = 'blowfish';
const CONFIG_PASSWORD_MIN_LENGTH = '6';
const CONFIG_MASTER_PASSWORD = 'lam';

// Configuración LDAP
const CONFIG_LDAP_URL = 'ldap://$LDAP_SERVER:389';
const CONFIG_LDAP_SUFFIX = '$BASE_DN';
const CONFIG_LDAP_BIND_USER = '$ADMIN_DN';
const CONFIG_LDAP_BIND_PASS = 'lam';

// Módulos activos
const CONFIG_MODULE_ACTIVE_COLUMNS = 'user,group';
const CONFIG_USER_MODULE = 'inetOrgPerson';
const CONFIG_GROUP_MODULE = 'posixGroup';

// Apariencia
const CONFIG_DEFAULT_LANGUAGE = 'en_US.UTF-8';
const CONFIG_LOGLEVEL = '3';
?>
EOL

# Configurar permisos
chown apache:apache /etc/ldap-account-manager/config.cfg
chmod 640 /etc/ldap-account-manager/config.cfg

# Configurar SELinux si está activo
if command -v getenforce >/dev/null 2>&1; then
    if [ "$(getenforce)" = "Enforcing" ]; then
        echo "Configurando SELinux..."
        setsebool -P httpd_can_network_connect on
        setsebool -P httpd_can_connect_ldap on
    fi
fi

# Configurar firewall
echo "Configurando firewall..."
dnf install -y firewalld
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# Iniciar y habilitar Apache
echo "Iniciando servicios..."
systemctl enable --now httpd

# Verificar que Apache esté funcionando
for i in {1..10}; do
    if systemctl is-active --quiet httpd && curl -s http://localhost > /dev/null; then
        echo "✅ Apache funcionando correctamente"
        break
    fi
    echo "Intento $i/10 - Esperando que Apache esté listo..."
    sleep 10
    systemctl restart httpd
done

# Crear página de información
cat > /var/www/html/index.html << EOL
<!DOCTYPE html>
<html>
<head>
    <title>LDAP Account Manager - Ready</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; text-align: center; }
        .success { color: green; font-size: 24px; }
        .info { margin: 20px 0; }
    </style>
</head>
<body>
    <div class="success">✅ LDAP Account Manager Instalado</div>
    <div class="info">
        <p><a href="/lam">Acceder a LAM</a></p>
        <p><strong>Credenciales:</strong></p>
        <p>Usuario: cn=admin,dc=amsa,dc=udl,dc=cat</p>
        <p>Contraseña: 1234</p>
    </div>
</body>
</html>
EOL

# Probar acceso a LAM
echo "Probando instalación de LAM..."
if curl -s http://localhost/lam | grep -q "LDAP Account Manager"; then
    echo "✅ LAM instalado correctamente"
else
    echo "⚠️  LAM puede tener problemas de instalación"
fi

echo "=== LDAP ACCOUNT MANAGER INSTALADO ==="
echo "🌐 URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/lam"
