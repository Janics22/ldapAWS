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

# Generar hash de contraseña admin
ADMIN_HASH=$(slappasswd -s "$ADMIN_PASSWORD")

# Iniciar slapd antes de modificar cn=config
systemctl enable slapd
systemctl start slapd
sleep 5

echo "=== CONFIGURANDO ROOTDN Y ROOTPW ==="

# Establecer olcRootDN correctamente
cat > /tmp/set-rootdn.ldif <<EOF
dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: $ADMIN_DN
EOF

ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/set-rootdn.ldif

# Establecer contraseña admin
cat > /tmp/set-rootpw.ldif <<EOF
dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $ADMIN_HASH
EOF

ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/set-rootpw.ldif

echo "=== CREANDO ESTRUCTURA BASE ==="

cat > /tmp/base.ldif <<EOF
dn: $BASE_DN
objectClass: top
objectClass: dcObject
objectClass: organization
o: AMSA Organization
dc: amsa

dn: cn=admin,$BASE_DN
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: admin
description: LDAP Administrator
userPassword: $ADMIN_HASH

dn: ou=users,$BASE_DN
objectClass: organizationalUnit
ou: users

dn: ou=groups,$BASE_DN
objectClass: organizationalUnit
ou: groups
EOF

ldapadd -x -D "$ADMIN_DN" -w "$ADMIN_PASSWORD" -f /tmp/base.ldif

echo "=== CREANDO USUARIOS Y GRUPOS ==="

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

# Admin user
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
userPassword: $ADMIN_HASH
EOF

ldapadd -x -D "$ADMIN_DN" -w "$ADMIN_PASSWORD" -f /tmp/users.ldif

echo "=== CONFIGURANDO FIREWALL ==="

systemctl enable firewalld
systemctl start firewalld
firewall-cmd --permanent --add-service=ldap
firewall-cmd --permanent --add-service=ldaps
firewall-cmd --reload

echo "=== SERVIDOR LDAP INSTALADO Y CONFIGURADO ==="
echo "Base DN: $BASE_DN"
echo "Admin DN: $ADMIN_DN"
echo "Contraseña: $ADMIN_PASSWORD"
