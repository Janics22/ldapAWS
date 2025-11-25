#!/bin/bash

# client_ldap.sh - Configuración completa del cliente LDAP
set -e

if [ -z "$1" ]; then
    echo "Error: Debe proporcionar la IP del servidor LDAP"
    exit 1
fi

LDAP_SERVER=$1
BASE_DN="dc=amsa,dc=udl,dc=cat"

echo "=== CONFIGURANDO CLIENTE LDAP COMPLETO ==="
echo "Servidor LDAP: $LDAP_SERVER"

# Instalar paquetes necesarios
echo "Instalando paquetes LDAP..."
dnf update -y
dnf install -y openldap-clients nss-pam-ldapd authselect openldap-devel

# Configurar /etc/openldap/ldap.conf
echo "Configurando cliente LDAP..."
cat > /etc/openldap/ldap.conf << EOL
BASE $BASE_DN
URI ldap://$LDAP_SERVER

TLS_CACERT /etc/openldap/certs/cacert.pem
TLS_REQCERT allow

SASL_NOCANON on
EOL

# Configurar PAM y NSS para usar LDAP
echo "Configurando PAM y NSS..."
authselect select sssd with-mkhomedir --force

# Configurar /etc/sssd/sssd.conf
cat > /etc/sssd/sssd.conf << EOL
[sssd]
config_file_version = 2
services = nss, pam
domains = default

[domain/default]
id_provider = ldap
auth_provider = ldap
ldap_uri = ldap://$LDAP_SERVER
ldap_search_base = $BASE_DN
ldap_id_use_start_tls = True
ldap_tls_cacert = /etc/openldap/certs/cacert.pem
cache_credentials = True
ldap_tls_reqcert = allow
EOL

chmod 600 /etc/sssd/sssd.conf

# Crear directorio para certificados
mkdir -p /etc/openldap/certs

# Reiniciar servicios
echo "Reiniciando servicios..."
systemctl restart sssd
systemctl enable sssd

# Esperar a que el servicio LDAP esté disponible
echo "Esperando a que el servidor LDAP esté disponible..."
for i in {1..30}; do
    if ldapsearch -x -H ldap://$LDAP_SERVER -b "$BASE_DN" "(objectClass=*)" 2>/dev/null | grep -q "dn:"; then
        break
    fi
    echo "Intento $i/30 - Esperando servidor LDAP..."
    sleep 10
done

# Probar conexión LDAP
echo "Probando conexión LDAP..."
if ldapsearch -x -H ldap://$LDAP_SERVER -b "$BASE_DN" "(objectClass=*)" 2>/dev/null | grep -q "dn:"; then
    echo "✅ Conexión LDAP exitosa"
    
    # Mostrar información de usuarios
    echo "=== Usuarios LDAP disponibles ==="
    ldapsearch -x -H ldap://$LDAP_SERVER -b "$BASE_DN" "(objectClass=inetOrgPerson)" cn uid | grep -E "(cn:|uid:)" | head -20
else
    echo "❌ Error en la conexión LDAP"
    echo "Intentando continuar con la configuración..."
fi

echo "=== CLIENTE LDAP CONFIGURADO COMPLETAMENTE ==="