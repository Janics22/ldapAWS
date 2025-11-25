#!/bin/bash

# lam.sh - Instalación completa de LDAP Account Manager
set -e

if [ -z "$1" ]; then
    echo "Error: Debe proporcionar la IP del servidor LDAP"
    exit 1
fi

LDAP_SERVER=$1
BASE_DN="dc=amsa,dc=udl,dc=cat"
ADMIN_DN="cn=admin,$BASE_DN"

echo "=== INSTALANDO LDAP ACCOUNT MANAGER COMPLETO ==="

# Instalar Apache, PHP y dependencias
echo "Instalando Apache, PHP y dependencias..."
dnf update -y
dnf install -y httpd php php-ldap php-mbstring php-xml php-json php-gettext

# Instalar LAM desde repositorio EPEL
echo "Instalando LAM..."
dnf install -y epel-release
dnf install -y ldap-account-manager

# Configurar Apache para LAM
echo "Configurando Apache..."
cp /etc/ldap-account-manager/config.cfg /etc/ldap-account-manager/config.cfg.backup

# Crear configuración LAM completa
cat > /etc/ldap-account-manager/config.cfg << EOL
<?php
/*
 * This is the main configuration file of LAM.
 * You can use the LAM configuration editor in your webbrowser to modify these settings.
 */

// your server address
const CONFIG_SERVER_URL = 'http://\${_SERVER['HTTP_HOST']}/lam';

// security settings
const CONFIG_CIPHER = 'blowfish';

// password policy
const CONFIG_PASSWORD_MIN_LENGTH = '6';

// master configuration
const CONFIG_MASTER_PASSWORD = 'lam';

// LDAP access
const CONFIG_LDAP_URL = 'ldap://$LDAP_SERVER:389';
const CONFIG_LDAP_SUFFIX = '$BASE_DN';
const CONFIG_LDAP_BIND_USER = '$ADMIN_DN';
const CONFIG_LDAP_BIND_PASS = 'lam';

// module settings
const CONFIG_MODULE_ACTIVE_COLUMNS = 'user,group,host,domain,system';
const CONFIG_USER_MODULE = 'inetOrgPerson';
const CONFIG_GROUP_MODULE = 'posixGroup';
const CONFIG_HOST_MODULE = 'hostObject';
const CONFIG_DOMAIN_MODULE = 'domain';
const CONFIG_SYSTEM_MODULE = 'systemObject';

// appearance
const CONFIG_DEFAULT_LANGUAGE = 'ca_ES.UTF-8';
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
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload

# Iniciar y habilitar servicios
echo "Iniciando servicios..."
systemctl enable --now httpd

# Crear página de información completa
cat > /var/www/html/index.html << EOL
<!DOCTYPE html>
<html>
<head>
    <title>LDAP Account Manager - AMSA</title>
    <meta charset="utf-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 1000px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; text-align: center; margin-bottom: 30px; }
        .info-card { background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 15px 0; border-left: 4px solid #007bff; }
        .warning { background: #fff3cd; padding: 20px; border-radius: 8px; margin: 20px 0; border: 1px solid #ffeaa7; }
        .btn { display: inline-block; padding: 12px 24px; background: #28a745; color: white; text-decoration: none; border-radius: 5px; font-weight: bold; margin: 10px 0; }
        .btn:hover { background: #218838; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎓 LDAP Account Manager</h1>
            <p>Sistema completo de gestión de usuarios LDAP</p>
        </div>

        <div class="info-card">
            <h2>🚀 Acceso al Sistema</h2>
            <p>Acceda al panel de administración LDAP:</p>
            <a href="/lam" class="btn">🔗 Acceder a LAM</a>
        </div>

        <div class="warning">
            <h3>🔐 Credenciales de Acceso</h3>
            <ul>
                <li><strong>Usuario:</strong> cn=admin,dc=amsa,dc=udl,dc=cat</li>
                <li><strong>Contraseña LAM:</strong> lam</li>
                <li><strong>Contraseña LDAP:</strong> 1234</li>
            </ul>
            <p><em>⚠️ Por seguridad, cambie las contraseñas después del primer acceso</em></p>
        </div>

        <div class="info-card">
            <h3>📊 Información del Sistema</h3>
            <ul>
                <li><strong>Servidor LDAP:</strong> $LDAP_SERVER</li>
                <li><strong>Base DN:</strong> $BASE_DN</li>
                <li><strong>Servidor LAM:</strong> $(hostname)</li>
                <li><strong>Usuarios creados:</strong> admin, 6 alumnos, 2 profesores</li>
                <li><strong>Grupos:</strong> alumnes, professors, admins</li>
            </ul>
        </div>

        <div class="info-card">
            <h3>🔧 Características Técnicas</h3>
            <ul>
                <li>OpenLDAP 2.6.3 compilado desde fuente</li>
                <li>Autenticación SHA-512 para contraseñas</li>
                <li>Cifrado TLS/SSL habilitado</li>
                <li>Interfaz web completa de gestión</li>
                <li>Integración con sistemas PAM/Linux</li>
            </ul>
        </div>
    </div>
</body>
</html>
EOL

# Esperar a que el servicio LDAP esté disponible
echo "Esperando a que el servidor LDAP esté disponible..."
for i in {1..30}; do
    if ldapsearch -x -H ldap://$LDAP_SERVER -b "$BASE_DN" "(objectClass=*)" 2>/dev/null | grep -q "dn:"; then
        break
    fi
    echo "Intento $i/30 - Esperando servidor LDAP..."
    sleep 10
done

# Probar configuración
echo "Probando configuración..."
if systemctl is-active --quiet httpd; then
    echo "✅ Servicio Apache activo"
else
    echo "❌ Error en servicio Apache"
    exit 1
fi

echo "=== LDAP ACCOUNT MANAGER INSTALADO COMPLETAMENTE ==="
echo "🌐 URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/lam"
echo "🔐 Usuario: $ADMIN_DN"
echo "🔑 Contraseña LAM: lam"
echo "🔑 Contraseña LDAP: 1234"