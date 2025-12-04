#!/bin/bash

#############################
# SERVER LDAP INSTALL SCRIPT
# Con hostname dinámico (AWS-friendly)
# Con usuarios iniciales: 6 alumnos y 2 profesores
#############################

set -e

# Variables
PATH_PKI="/etc/openldap/certs"
OPENLDAP_VERSION="2.6.7"
country="US"
state="California"
locality="San Francisco"
organization="ExampleCorp"
organizationalunit="IT"
email="admin@example.com"
BASEDN="dc=example,dc=com"

#############################
# Obtener hostname dinámico
#############################
FQDN=$(hostname -f 2>/dev/null || hostname)
echo "➡ Hostname detectado: $FQDN"

#############################
# Instalar dependencias
#############################
dnf install -y gcc make cyrus-sasl-devel openssl-devel libtool-ltdl openssl wget tar \
    autoconf libtool libdb-devel libdb-utils libuuid-devel libevent-devel

#############################
# Descargar y compilar OpenLDAP
#############################
cd /usr/local/src
wget https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-${OPENLDAP_VERSION}.tgz
tar -xvf openldap-${OPENLDAP_VERSION}.tgz
cd openldap-${OPENLDAP_VERSION}

./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --enable-slapd \
    --with-tls=openssl \
    --enable-dynamic \
    --enable-overlays \
    --enable-modules \
    --enable-mdb=yes

make depend
make -j"$(nproc)"
make install

#############################
# Crear directorios y permisos
#############################
mkdir -p /var/lib/ldap
mkdir -p /etc/openldap/slapd.d
mkdir -p "$PATH_PKI"

chown -R ldap:ldap /var/lib/ldap
chown -R ldap:ldap /etc/openldap/slapd.d
chmod 700 "$PATH_PKI"

#############################
# Crear certificado TLS dinámico
#############################
echo "➡ Generando certificado TLS para CN=$FQDN"

openssl req -days 500 -newkey rsa:4096 \
    -keyout "$PATH_PKI/ldapkey.pem" -nodes \
    -sha256 -x509 -out "$PATH_PKI/ldapcert.pem" \
    -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$FQDN/emailAddress=$email"

chown ldap:ldap "$PATH_PKI"/*.pem
chmod 600 "$PATH_PKI"/*.pem

#############################
# Inicializar base de datos
#############################
slapadd -n0 -F /etc/openldap/slapd.d <<EOF
dn: $BASEDN
objectClass: top
objectClass: domain
dc: example
EOF

#############################
# Configurar TLS en cn=config
#############################
cat << EOF | ldapmodify -Y EXTERNAL -H ldapi:///
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: $PATH_PKI/ldapcert.pem
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: $PATH_PKI/ldapkey.pem
-
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: $PATH_PKI/ldapcert.pem
EOF

#############################
# Configurar Systemd
#############################
cat <<EOF > /usr/lib/systemd/system/slapd.service
[Unit]
Description=OpenLDAP Server Daemon
After=network.target

[Service]
Type=forking
User=ldap
Group=ldap
ExecStartPre=/usr/libexec/openldap/check-config.sh
ExecStart=/usr/sbin/slapd -u ldap -h "ldap:/// ldaps:/// ldapi:///"
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/var/run/openldap/slapd.pid

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now slapd

#############################
# Crear usuarios: 6 alumnos y 2 profesores
#############################
cat <<EOF > /tmp/users.ldif
dn: ou=Alumnos,$BASEDN
objectClass: organizationalUnit
ou: Alumnos

dn: ou=Profesores,$BASEDN
objectClass: organizationalUnit
ou: Profesores

# Alumnos
dn: uid=alumno1,ou=Alumnos,$BASEDN
objectClass: inetOrgPerson
cn: Alumno Uno
sn: Uno
uid: alumno1
userPassword: alumno1pass

dn: uid=alumno2,ou=Alumnos,$BASEDN
objectClass: inetOrgPerson
cn: Alumno Dos
sn: Dos
uid: alumno2
userPassword: alumno2pass

dn: uid=alumno3,ou=Alumnos,$BASEDN
objectClass: inetOrgPerson
cn: Alumno Tres
sn: Tres
uid: alumno3
userPassword: alumno3pass

dn: uid=alumno4,ou=Alumnos,$BASEDN
objectClass: inetOrgPerson
cn: Alumno Cuatro
sn: Cuatro
uid: alumno4
userPassword: alumno4pass

dn: uid=alumno5,ou=Alumnos,$BASEDN
objectClass: inetOrgPerson
cn: Alumno Cinco
sn: Cinco
uid: alumno5
userPassword: alumno5pass

dn: uid=alumno6,ou=Alumnos,$BASEDN
objectClass: inetOrgPerson
cn: Alumno Seis
sn: Seis
uid: alumno6
userPassword: alumno6pass

# Profesores
dn: uid=profesor1,ou=Profesores,$BASEDN
objectClass: inetOrgPerson
cn: Profesor Uno
sn: Uno
uid: profesor1
userPassword: profesor1pass

dn: uid=profesor2,ou=Profesores,$BASEDN
objectClass: inetOrgPerson
cn: Profesor Dos
sn: Dos
uid: profesor2
userPassword: profesor2pass
EOF

ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/users.ldif

#############################
# Salida final
#############################
echo "✔ Instalación completada"
echo "✔ OpenLDAP compilado e iniciado"
echo "✔ Certificado TLS generado para: $FQDN"
echo "✔ LDAPS escuchando en el puerto 636"
echo "✔ 6 alumnos y 2 profesores creados en LDAP"
