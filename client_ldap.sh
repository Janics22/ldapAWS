#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Error: Proporciona IP del servidor LDAP"
    exit 1
fi

LDAP_SERVER="ldap-server.ldap.local"
BASE_DN="dc=amsa,dc=udl,dc=cat"

echo "=== CONFIGURANDO CLIENTE LDAP ==="

# Esperar servidor LDAP
echo "Esperando servidor LDAP en $LDAP_SERVER:389..."
until nc -z $LDAP_SERVER 389; do
    echo "Servidor LDAP no disponible, esperando 10 segundos..."
    sleep 10
done

echo "Servidor LDAP detectado."

# Actualizar e instalar paquetes
dnf update -y
dnf install -y openldap-clients sssd sssd-tools authselect oddjob-mkhomedir

# Configurar LDAP
cat > /etc/openldap/ldap.conf <<EOF
BASE $BASE_DN
URI ldap://$LDAP_SERVER
TLS_REQCERT allow
EOF

# Configurar autenticación con authselect
authselect select sssd with-mkhomedir --force

# Configurar SSSD
cat > /etc/sssd/sssd.conf <<EOF
[sssd]
services = nss, pam
domains = default
config_file_version = 2

[domain/default]
id_provider = ldap
auth_provider = ldap
chpass_provider = ldap
ldap_uri = ldap://$LDAP_SERVER
ldap_search_base = $BASE_DN
cache_credentials = True
enumerate = True
ldap_tls_reqcert = allow
EOF

# Establecer permisos correctos
chmod 600 /etc/sssd/sssd.conf
chown root:root /etc/sssd/sssd.conf

# Reiniciar y habilitar SSSD
systemctl restart sssd
systemctl enable sssd

echo "=== CLIENTE LDAP CONFIGURADO ==="
