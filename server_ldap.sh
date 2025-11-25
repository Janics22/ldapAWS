#!/bin/bash

# server_ldap.sh - Instalación completa del servidor LDAP
set -e

echo "=== INICIANDO INSTALACIÓN COMPLETA DEL SERVIDOR LDAP ==="

# Variables de configuración
BASE_DN="dc=amsa,dc=udl,dc=cat"
ADMIN_PASSWORD="1234"
PATH_PKI="/etc/openldap/certs"

# Actualizar sistema
dnf update -y

# Instalar dependencias completas
echo "Instalando dependencias..."
dnf install -y \
    cyrus-sasl-devel make libtool autoconf libtool-ltdl-devel \
    openssl-devel libdb-devel tar gcc perl perl-devel wget vim \
    net-tools openldap-servers openldap-clients

# Descargar y compilar OpenLDAP desde fuente
echo "Descargando y compilando OpenLDAP..."
VER="2.6.3"
cd /tmp
wget -q ftp://ftp.openldap.org/pub/OpenLDAP/openldap-release/openldap-$VER.tgz
tar xzf openldap-$VER.tgz
cd openldap-$VER

./configure --prefix=/usr --sysconfdir=/etc --disable-static \
    --enable-debug --with-tls=openssl --with-cyrus-sasl --enable-dynamic \
    --enable-crypt --enable-spasswd --enable-slapd --enable-modules \
    --enable-rlookups --disable-sql --enable-ppolicy --enable-syslog

make depend
make
make install

# Instalar módulo SHA2
echo "Instalando módulo SHA2..."
cd contrib/slapd-modules/passwd/sha2
make
make install

# Crear usuario y grupo para LDAP
echo "Creando usuario y grupo LDAP..."
groupadd -g 55 ldap || true
useradd -r -M -d /var/lib/openldap -u 55 -g 55 -s /usr/sbin/nologin ldap || true

# Crear directorios necesarios
mkdir -p /var/lib/openldap
mkdir -p /etc/openldap/slapd.d
mkdir -p $PATH_PKI

# Asignar permisos
chown -R ldap:ldap /var/lib/openldap
chown -R ldap:ldap /etc/openldap/slapd.d

# Crear archivo de servicio systemd
echo "Configurando servicio systemd..."
cat > /etc/systemd/system/slapd.service << 'EOL'
[Unit]
Description=OpenLDAP Server Daemon
After=syslog.target network-online.target
Documentation=man:slapd
Documentation=man:slapd-mdb

[Service]
Type=forking
PIDFile=/var/lib/openldap/slapd.pid
Environment="SLAPD_URLS=ldap:/// ldapi:/// ldaps:///"
Environment="SLAPD_OPTIONS=-F /etc/openldap/slapd.d"
ExecStart=/usr/libexec/slapd -u ldap -g ldap -h ${SLAPD_URLS} $SLAPD_OPTIONS

[Install]
WantedBy=multi-user.target
EOL

# Generar contraseña hash
echo "Generando hash de contraseña..."
HASHED_PASSWORD=$(slappasswd -h "{SSHA512}" -s "$ADMIN_PASSWORD")

# Crear configuración LDAP completa
echo "Creando configuración LDAP..."
cat > /etc/openldap/slapd.ldif << EOL
dn: cn=config
objectClass: olcGlobal
cn: config
olcArgsFile: /var/lib/openldap/slapd.args
olcPidFile: /var/lib/openldap/slapd.pid
olcTLSCipherSuite: TLSv1.2:HIGH:!aNULL:!eNULL
olcTLSProtocolMin: 3.3

dn: cn=schema,cn=config
objectClass: olcSchemaConfig
cn: schema

dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModulepath: /usr/libexec/openldap
olcModuleload: back_mdb.la

dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModulepath: /usr/local/libexec/openldap
olcModuleload: pw-sha2.la

include: file:///etc/openldap/schema/core.ldif
include: file:///etc/openldap/schema/cosine.ldif
include: file:///etc/openldap/schema/nis.ldif
include: file:///etc/openldap/schema/inetorgperson.ldif

dn: olcDatabase=frontend,cn=config
objectClass: olcDatabaseConfig
objectClass: olcFrontendConfig
olcDatabase: frontend
olcPasswordHash: {SSHA512}
olcAccess: to dn.base="cn=Subschema" by * read
olcAccess: to *
  by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by * none

dn: olcDatabase=config,cn=config
objectClass: olcDatabaseConfig
olcDatabase: config
olcRootDN: cn=config
olcAccess: to *
  by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by * none
EOL

# Cargar configuración
slapadd -n 0 -F /etc/openldap/slapd.d -l /etc/openldap/slapd.ldif
chown -R ldap:ldap /etc/openldap/slapd.d

# Iniciar servicio
systemctl daemon-reload
systemctl enable --now slapd

# Configurar base de datos
echo "Configurando base de datos..."
cat > /etc/openldap/rootdn.ldif << EOL
dn: olcDatabase=mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: mdb
olcDbMaxSize: 42949672960
olcDbDirectory: /var/lib/openldap
olcSuffix: $BASE_DN
olcRootDN: cn=admin,$BASE_DN
olcRootPW: $HASHED_PASSWORD
olcDbIndex: uid pres,eq
olcDbIndex: cn,sn pres,eq,approx,sub
olcDbIndex: mail pres,eq,sub
olcDbIndex: objectClass pres,eq
olcDbIndex: loginShell pres,eq
olcAccess: to attrs=userPassword,shadowLastChange,shadowExpire
  by self write
  by anonymous auth
  by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by dn.subtree="ou=system,$BASE_DN" read
  by * none
olcAccess: to dn.subtree="ou=system,$BASE_DN"
  by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by * none
olcAccess: to dn.subtree="$BASE_DN"
  by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by users read
  by * none
EOL

ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/rootdn.ldif

# Crear estructura base
echo "Creando estructura base..."
cat > /etc/openldap/basedn.ldif << EOL
dn: $BASE_DN
objectClass: dcObject
objectClass: organization
objectClass: top
o: AMSA
dc: amsa

dn: ou=groups,$BASE_DN
objectClass: organizationalUnit
objectClass: top
ou: groups

dn: ou=users,$BASE_DN
objectClass: organizationalUnit
objectClass: top
ou: users

dn: ou=system,$BASE_DN
objectClass: organizationalUnit
objectClass: top
ou: system
EOL

ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/basedn.ldif

# Crear usuarios y grupos completos
echo "Creando usuarios y grupos..."
cat > /etc/openldap/users.ldif << EOL
dn: cn=osproxy,ou=system,$BASE_DN
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: osproxy
userPassword: $HASHED_PASSWORD
description: OS proxy for resolving UIDs/GIDs

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
objectClass: top
cn: Admin User
sn: Admin
uid: admin
uidNumber: 1000
gidNumber: 10002
homeDirectory: /home/admin
loginShell: /bin/bash
userPassword: $HASHED_PASSWORD

# Alumnes (6 usuarios)
dn: uid=alumne1,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: top
cn: Alumne One
sn: One
uid: alumne1
uidNumber: 1001
gidNumber: 10000
homeDirectory: /home/alumne1
loginShell: /bin/bash
userPassword: $HASHED_PASSWORD

dn: uid=alumne2,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: top
cn: Alumne Two
sn: Two
uid: alumne2
uidNumber: 1002
gidNumber: 10000
homeDirectory: /home/alumne2
loginShell: /bin/bash
userPassword: $HASHED_PASSWORD

dn: uid=alumne3,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: top
cn: Alumne Three
sn: Three
uid: alumne3
uidNumber: 1003
gidNumber: 10000
homeDirectory: /home/alumne3
loginShell: /bin/bash
userPassword: $HASHED_PASSWORD

dn: uid=alumne4,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: top
cn: Alumne Four
sn: Four
uid: alumne4
uidNumber: 1004
gidNumber: 10000
homeDirectory: /home/alumne4
loginShell: /bin/bash
userPassword: $HASHED_PASSWORD

dn: uid=alumne5,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: top
cn: Alumne Five
sn: Five
uid: alumne5
uidNumber: 1005
gidNumber: 10000
homeDirectory: /home/alumne5
loginShell: /bin/bash
userPassword: $HASHED_PASSWORD

dn: uid=alumne6,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: top
cn: Alumne Six
sn: Six
uid: alumne6
uidNumber: 1006
gidNumber: 10000
homeDirectory: /home/alumne6
loginShell: /bin/bash
userPassword: $HASHED_PASSWORD

# Professors (2 usuarios)
dn: uid=professor1,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: top
cn: Professor One
sn: Professor
uid: professor1
uidNumber: 2001
gidNumber: 10001
homeDirectory: /home/professor1
loginShell: /bin/bash
userPassword: $HASHED_PASSWORD

dn: uid=professor2,ou=users,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: top
cn: Professor Two
sn: Professor
uid: professor2
uidNumber: 2002
gidNumber: 10001
homeDirectory: /home/professor2
loginShell: /bin/bash
userPassword: $HASHED_PASSWORD
EOL

ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/users.ldif

# Configurar TLS
echo "Configurando TLS..."
HOSTNAME=$(hostname)
openssl req -days 365 -newkey rsa:2048 \
    -keyout "$PATH_PKI/ldapkey.pem" -nodes \
    -sha256 -x509 -out "$PATH_PKI/ldapcert.pem" \
    -subj "/C=ES/ST=Catalunya/L=Lleida/O=UdL/OU=AMSA/CN=$HOSTNAME/emailAddress=admin@udl.cat"

chown ldap:ldap "$PATH_PKI/ldapkey.pem"
chmod 400 "$PATH_PKI/ldapkey.pem"
cat "$PATH_PKI/ldapcert.pem" > "$PATH_PKI/cacerts.pem"

cat > /etc/openldap/add-tls.ldif << EOL
dn: cn=config
changetype: modify
add: olcTLSCACertificateFile
olcTLSCACertificateFile: $PATH_PKI/cacerts.pem
-
add: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: $PATH_PKI/ldapkey.pem
-
add: olcTLSCertificateFile
olcTLSCertificateFile: $PATH_PKI/ldapcert.pem
EOL

ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/add-tls.ldif

# Reiniciar servicio para aplicar TLS
systemctl restart slapd

# Configurar firewall
echo "Configurando firewall..."
dnf install -y firewalld
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ldap
firewall-cmd --permanent --add-service=ldaps
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload

echo "=== SERVIDOR LDAP INSTALADO COMPLETAMENTE ==="
echo "Base DN: $BASE_DN"
echo "Usuario admin: cn=admin,$BASE_DN"
echo "Contraseña: $ADMIN_PASSWORD"