#!/bin/bash
set -e

echo "=== INICIANDO INSTALACIÓN SERVIDOR LDAP ==="

# Variables
BASE_DN="dc=amsa,dc=udl,dc=cat"
ADMIN_PASSWORD="1234"
CERT_DIR="/etc/openldap/certs"
HOSTNAME=$(hostname -f)

# Actualizar sistema
dnf update -y

# Instalar dependencias
dnf install -y openldap-servers openldap-clients openssl net-tools firewalld

# Configurar directorios
mkdir -p /var/lib/ldap /etc/openldap/slapd.d
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown -R ldap:ldap /var/lib/ldap /etc/openldap/slapd.d

# Iniciar y habilitar slapd
systemctl enable slapd
systemctl start slapd

# Crear estructura base
cat > /tmp/base.ldif <<EOF
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

ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/base.ldif

# Crear grupos y usuarios
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

ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/users.ldif

# Configurar TLS
mkdir -p $CERT_DIR
chmod 700 $CERT_DIR
chown ldap:ldap $CERT_DIR

openssl req -new -x509 -nodes -days 365 \
    -out $CERT_DIR/cacerts.pem \
    -keyout $CERT_DIR/ldapkey.pem \
    -subj "/C=ES/ST=Catalonia/L=Barcelona/O=AMSA/OU=IT/CN=$HOSTNAME/emailAddress=admin@udl.cat"

chown ldap:ldap $CERT_DIR/*.pem
chmod 600 $CERT_DIR/*.pem

# Crear LDIF para TLS
cat > /tmp/slapd_tls.ldif <<EOF
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: $CERT_DIR/cacerts.pem
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: $CERT_DIR/ldapkey.pem
-
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: $CERT_DIR/cacerts.pem
EOF

ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/slapd_tls.ldif

# Reiniciar slapd para aplicar TLS
systemctl restart slapd

# Configurar firewall
systemctl enable firewalld
systemctl start firewalld
firewall-cmd --permanent --add-service=ldap
firewall-cmd --permanent --add-service=ldaps
firewall-cmd --reload

echo "=== SERVIDOR LDAP INSTALADO Y CONFIGURADO ==="
echo "Base DN: $BASE_DN"
echo "Usuario admin: cn=admin,$BASE_DN"
echo "Contraseña: $ADMIN_PASSWORD"
echo "LDAPS activo en puerto 636"
