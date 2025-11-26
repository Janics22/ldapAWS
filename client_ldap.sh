#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Error: Proporciona IP del servidor LDAP"
    exit 1
fi

LDAP_SERVER=$1
BASE_DN="dc=amsa,dc=udl,dc=cat"

echo "=== CONFIGURANDO CLIENTE LDAP ==="

# Esperar servidor LDAP
echo "Esperando servidor LDAP..."
until nc -z $LDAP_SERVER 389; do
    sleep 10
done

# Instalar paquetes
dnf update -y
dnf install -y openldap-clients nss-pam-ldapd authselect
dnf install -y httpd php php-ldap php-mbstring php-gd php-gmp php-zip
sudo systemctl enable --now httpd


# Configurar LDAP
cat > /etc/openldap/ldap.conf << EOF
BASE $BASE_DN
URI ldap://$LDAP_SERVER
TLS_REQCERT allow
EOF

# Configurar autenticación
authselect select sssd with-mkhomedir --force

# Configurar SSSD
cat > /etc/sssd/sssd.conf << EOF
[sssd]
services = nss, pam
domains = default

[domain/default]
id_provider = ldap
auth_provider = ldap
ldap_uri = ldap://$LDAP_SERVER
ldap_search_base = $BASE_DN
cache_credentials = True
EOF

chmod 600 /etc/sssd/sssd.conf
systemctl restart sssd
systemctl enable sssd

echo "=== CLIENTE LDAP CONFIGURADO ==="
