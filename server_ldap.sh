#!/bin/bash
set -e

echo "=== INICIANDO INSTALACIÓN SERVIDOR LDAP ==="

# Variables
BASE_DN="dc=amsa,dc=udl,dc=cat"
ADMIN_PASSWORD="1234"

# Actualizar sistema
dnf update -y

# Instalar dependencias
sudo dnf install \
cyrus-sasl-devel make libtool autoconf libtool-ltdl-devel \
openldap-clients openldap-servers openldap-devel \
libdb-devel tar gcc perl perl-devel wget vim firewalld net-tools openssl -y

# Configurar directorios
mkdir -p /var/lib/ldap
mkdir -p /etc/openldap/slapd.d
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap:ldap /var/lib/ldap/*

# Configurar slapd
cat > /etc/openldap/slapd.conf << EOF
include /etc/openldap/schema/core.schema
include /etc/openldap/schema/cosine.schema
include /etc/openldap/schema/nis.schema
include /etc/openldap/schema/inetorgperson.schema

pidfile /var/run/openldap/slapd.pid
argsfile /var/run/openldap/slapd.args

modulepath /usr/lib64/openldap
moduleload back_mdb.la

database mdb
suffix "$BASE_DN"
rootdn "cn=admin,$BASE_DN"
rootpw $(slappasswd -s $ADMIN_PASSWORD)
directory /var/lib/ldap

index objectClass eq,pres
index ou,cn,mail,surname,givenname eq,pres,sub
index uidNumber,gidNumber,loginShell eq,pres
index uid,memberUid eq,pres,sub
index nisMapName,nisMapEntry eq,pres,sub
EOF

# Configurar dominio base
cat > /tmp/base.ldif << EOF
dn: $BASE_DN
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

# Configurar usuarios
cat > /tmp/users.ldif << EOF
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

# Alumnos (6 usuarios)
dn: uid=alumne1,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Alumne One
sn: One
uid: alumne1
uidNumber: 1001
gidNumber: 10000
homeDirectory: /home/alumne1
userPassword: $(slappasswd -s $ADMIN_PASSWORD)

dn: uid=alumne2,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Alumne Two
sn: Two
uid: alumne2
uidNumber: 1002
gidNumber: 10000
homeDirectory: /home/alumne2
userPassword: $(slappasswd -s $ADMIN_PASSWORD)

dn: uid=alumne3,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Alumne Three
sn: Three
uid: alumne3
uidNumber: 1003
gidNumber: 10000
homeDirectory: /home/alumne3
userPassword: $(slappasswd -s $ADMIN_PASSWORD)

dn: uid=alumne4,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Alumne Four
sn: Four
uid: alumne4
uidNumber: 1004
gidNumber: 10000
homeDirectory: /home/alumne4
userPassword: $(slappasswd -s $ADMIN_PASSWORD)

dn: uid=alumne5,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Alumne Five
sn: Five
uid: alumne5
uidNumber: 1005
gidNumber: 10000
homeDirectory: /home/alumne5
userPassword: $(slappasswd -s $ADMIN_PASSWORD)

dn: uid=alumne6,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Alumne Six
sn: Six
uid: alumne6
uidNumber: 1006
gidNumber: 10000
homeDirectory: /home/alumne6
userPassword: $(slappasswd -s $ADMIN_PASSWORD)

# Professors (2 usuarios)
dn: uid=professor1,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Professor One
sn: Professor
uid: professor1
uidNumber: 2001
gidNumber: 10001
homeDirectory: /home/professor1
userPassword: $(slappasswd -s $ADMIN_PASSWORD)

dn: uid=professor2,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Professor Two
sn: Professor
uid: professor2
uidNumber: 2002
gidNumber: 10001
homeDirectory: /home/professor2
userPassword: $(slappasswd -s $ADMIN_PASSWORD)
EOF

# Iniciar servicios
systemctl enable slapd
systemctl start slapd

# Añadir estructura base y usuarios
sleep 10
ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/base.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/users.ldif

# Configurar firewall
systemctl enable firewalld
systemctl start firewalld
firewall-cmd --permanent --add-service=ldap
firewall-cmd --permanent --add-service=ldaps
firewall-cmd --reload

echo "=== SERVIDOR LDAP INSTALADO ==="
echo "Base DN: $BASE_DN"
echo "Usuario: cn=admin,$BASE_DN"
echo "Contraseña: $ADMIN_PASSWORD"
