#!/bin/bash
set -e

echo "=== INICIANDO INSTALACIÓN SERVIDOR LDAP EN AL2023 ==="

# Variables
BASE_DN="dc=amsa,dc=udl,dc=cat"
ADMIN_DN="cn=admin,$BASE_DN"
ADMIN_PASSWORD="1234"

# Actualizar sistema
dnf update -y

# Instalar OpenLDAP y herramientas
dnf install -y openldap-servers openldap-clients openssl net-tools firewalld

# Inicializar base de datos slapd
if [ ! -f /var/lib/ldap/DB_CONFIG ]; then
    cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
    chown ldap:ldap /var/lib/ldap/DB_CONFIG
fi

# Configurar contraseña de admin para cn=config
ADMIN_HASH=$(slappasswd -s $ADMIN_PASSWORD)

cat > /tmp/ldap-admin.ldif <<EOF
dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $ADMIN_HASH
EOF

# Iniciar slapd
systemctl enable slapd
systemctl start slapd
sleep 5

# Aplicar contraseña admin
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/ldap-admin.ldif

# Crear estructura base
cat > /tmp/base.ldif <<EOF
dn: $BASE_DN
objectClass: top
objectClass: dcObject
objectClass: organization
o: AMSA Organization
dc: amsa

dn: cn=admin,$BASE_DN
objectClass: organizationalRole
cn: admin
description: LDAP Administrator

dn: ou=users,$BASE_DN
objectClass: organizationalUnit
ou: users

dn: ou=groups,$BASE_DN
objectClass: organizationalUnit
ou: groups
EOF

ldapadd -x -D "$ADMIN_DN" -w "$ADMIN_PASSWORD" -f /tmp/base.ldif

# Crear usuarios y grupos de ejemplo
cat > /tmp/users.ldif <<EOF
# Grupos
dn: cn=alumnes,ou=groups,$BASE_DN
objectClass: posixGroup
cn: alumnes
gidNumber: 10000

dn: cn=professors,ou=groups,$BASE_DN
objectClass: posixGroup
cn: professors
gidNumber: 10001

dn: cn=admins,ou=groups,$BASE_DN
objectClass: posixGroup
cn: admins
gidNumber: 10002

# Admin
dn: uid=admin,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Admin User
sn: Admin
uid: admin
uidNumber: 1000
gidNumber: 10002
homeDirectory: /home/admin
userPassword: $(slappasswd -s $ADMIN_PASSWORD)
EOF

ldapadd -x -D "$ADMIN_DN" -w "$ADMIN_PASSWORD" -f /tmp/users.ldif

# Configurar firewall
dnf install -y firewalld
systemctl enable firewalld
systemctl start firewalld
firewall-cmd --permanent --add-service=ldap
firewall-cmd --permanent --add-service=ldaps
firewall-cmd --reload

echo "=== SERVIDOR LDAP INSTALADO ==="
echo "Base DN: $BASE_DN"
echo "Usuario admin: $ADMIN_DN"
echo "Contraseña: $ADMIN_PASSWORD"
