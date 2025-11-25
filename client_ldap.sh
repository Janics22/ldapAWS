#!/bin/bash
# client_ldap.sh - Configuración robusta del cliente LDAP
set -e

if [ -z "$1" ]; then
    echo "Error: Debe proporcionar la IP del servidor LDAP"
    exit 1
fi

LDAP_SERVER=$1
BASE_DN="dc=amsa,dc=udl,dc=cat"

echo "=== CONFIGURANDO CLIENTE LDAP ==="
echo "Servidor LDAP: $LDAP_SERVER"

# Espera mejorada con múltiples métodos
echo "Esperando a que el servidor LDAP esté completamente listo..."

# Método 1: Esperar por el archivo de señal (si está en la misma AZ)
for i in {1..30}; do
    if ssh -o StrictHostKeyChecking=no ec2-user@$LDAP_SERVER "test -f /tmp/ldap_server_ready" 2>/dev/null; then
        echo "Servidor LDAP listo (señal detectada)"
        break
    fi
    echo "Intento $i/30 - Esperando señal del servidor LDAP..."
    sleep 30
done

# Método 2: Esperar por el puerto LDAP
for i in {1..20}; do
    if nc -z $LDAP_SERVER 389; then
        echo "Puerto LDAP accesible"
        break
    fi
    echo "Intento $i/20 - Esperando puerto LDAP..."
    sleep 15
done

# Método 3: Esperar por respuesta LDAP
for i in {1..15}; do
    if ldapsearch -x -H ldap://$LDAP_SERVER -b "$BASE_DN" -s base "(objectClass=*)" 2>/dev/null | grep -q "dn:"; then
        echo "LDAP respondiendo correctamente"
        break
    fi
    echo "Intento $i/15 - Esperando respuesta LDAP..."
    sleep 20
done

# Instalar paquetes necesarios
echo "Instalando paquetes LDAP..."
dnf update -y
dnf install -y openldap-clients nss-pam-ldapd authselect openldap-devel openssh-clients

# Configurar cliente LDAP
echo "Configurando cliente LDAP..."
cat > /etc/openldap/ldap.conf << EOL
BASE $BASE_DN
URI ldap://$LDAP_SERVER
TLS_REQCERT allow
SASL_NOCANON on
EOL

# Configurar autenticación
echo "Configurando autenticación LDAP..."
authselect select sssd with-mkhomedir --force

# Configurar SSSD
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
ldap_tls_reqcert = allow
cache_credentials = True
EOL

chmod 600 /etc/sssd/sssd.conf

# Reiniciar servicios
systemctl restart sssd
systemctl enable sssd

# Probar conexión
echo "Probando conexión LDAP..."
if ldapsearch -x -H ldap://$LDAP_SERVER -b "$BASE_DN" "(objectClass=*)" 2>/dev/null | grep -q "dn:"; then
    echo "✅ Conexión LDAP exitosa"
else
    echo "⚠️  Conexión LDAP con problemas, pero continuando..."
fi

echo "=== CLIENTE LDAP CONFIGURADO ==="
