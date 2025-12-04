#!/bin/bash
set -e

echo "=== INICIANDO INSTALACIÓN SERVIDOR LDAP ==="

# Variables
BASE_DN="dc=amsa,dc=udl,dc=cat"
ADMIN_PASSWORD="1234"
FQDN=$(hostname -f)   # <-- Hostname dinámico de AWS
CERT_DIR="/etc/openldap/certs"

echo "[INFO] Hostname detectado: $FQDN"

# Actualizar sistema
dnf update -y

# Instalar dependencias
dnf install -y openldap-servers openldap-clients openssl net-tools firewalld

# Crear directorios
mkdir -p /var/lib/ldap
mkdir -p /etc/openldap/slapd.d
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap:ldap /var/lib/ldap/*

##############################################
# GENERAR CERTIFICADOS TLS AUTOMÁTICOS
##############################################
echo "[INFO] Generando certificados TLS..."

mkdir -p $CERT_DIR
chmod 700 $CERT_DIR

openssl req -x509 -nodes -days 365 \
  -subj "/CN=$FQDN" \
  -newkey rsa:2048 \
  -keyout $CERT_DIR/ldap.key \
  -out $CERT_DIR/ldap.crt

chown ldap:ldap $CERT_DIR/*
chmod 600 $CERT_DIR/*

##############################################
# CONFIGURAR SLAPD.CONF (añadir TLS)
##############################################
echo "[INFO] Configurando slapd.conf..."

cat > /etc/openldap/slapd.conf << EOF
include /etc/openldap/schema/core.schema
include /etc/openldap/schema/cosine.schema
include /etc/openldap/schema/nis.schema
include /etc/openldap/schema/inetorgperson.schema

pidfile /var/run/openldap/slapd.pid
argsfile /var/run/openldap/slapd.args

TLSCACertificateFile $CERT_DIR/ldap.crt
TLSCertificateFile $CERT_DIR/ldap.crt
TLSCertificateKeyFile $CERT_DIR/ldap.key

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

##############################################
# CREAR ESTRUCTURA BASE
##############################################
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

##############################################
# USUARIOS
##############################################
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
EOF

# Añadir los usuarios alumnos (loop)
for i in {1..6}; do
cat >> /tmp/users.ldif << EOF
dn: uid=alumne$i,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Alumne $i
sn: Number$i
uid: alumne$i
uidNumber: $((1000 + $i))
gidNumber: 10000
homeDirectory: /home/alumne$i
userPassword: $(slappasswd -s $ADMIN_PASSWORD)

EOF
done

# Profesores
cat >> /tmp/users.ldif << EOF
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

##############################################
# INICIAR Y POBLAR LDAP
##############################################
systemctl enable slapd
systemctl restart slapd

sleep 5

ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/base.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/users.ldif

##############################################
# FIREWALL
##############################################
systemctl enable firewalld
systemctl start firewalld
firewall-cmd --permanent --add-service=ldap
firewall-cmd --permanent --add-service=ldaps
firewall-cmd --reload

echo "======================================================"
echo "=== SERVIDOR LDAP INSTALADO CON TLS AUTOMÁTICO ==="
echo "Base DN: $BASE_DN"
echo "Admin: cn=admin,$BASE_DN"
echo "Contraseña: $ADMIN_PASSWORD"
echo "Hostname TLS: $FQDN"
echo "======================================================"
