#!/bin/bash
set -e

# ========================
#  CONFIG
# ========================
if [ -z "$1" ]; then
    echo "Error: Falta la IP del servidor LDAP"
    exit 1
fi

LDAP_SERVER=$1
BASE_DN="dc=amsa,dc=udl,dc=cat"
ADMIN_DN="cn=admin,$BASE_DN"

echo "=== INICIANDO INSTALACIÓN DE LAM EN AMAZON LINUX 2023 ==="


# ========================
#  ESPERAR LDAP
# ========================
echo "Esperando servidor LDAP..."
until nc -z $LDAP_SERVER 389; do
    echo "LDAP no disponible, esperando 10s..."
    sleep 10
done


# ========================
#  SISTEMA + PHP + EXTENSIONES
# ========================
dnf update -y

sudo dnf install -y httpd php php-ldap php-mbstring php-gd php-gmp php-zip
sudo systemctl enable --now httpd


# ========================
#  DESCARGAR LAM 9.0
# ========================
sudo wget https://github.com/LDAPAccountManager/lam/releases/download/9.0.RC1/ldap-account-manager-9.0.RC1-0.fedora.1.noarch.rpm
sudo dnf install -y ldap-account-manager-9.0.RC1-0.fedora.1.noarch.rpm

mv ldap-account-manager-9.0.RC1-0.fedora.1.noarch.rpm /var/www/html/lam
chown -R apache:apache /var/www/html/lam



# ========================
#  CONFIGURACIÓN DEL PERFIL default
# ========================
cat > /var/lib/ldap-account-manager/config/profiles/default.conf << EOF
# Server settings
ServerURL: ldap://$LDAP_SERVER:389
useTLS: no
followReferrals: false
pagedResults: false
referentialIntegrityOverlay: false
searchLimit: 0

# LDAP suffix
defaultLanguage: en_GB.utf8:UTF-8:English (Great Britain)
Passwd: {SSHA}gVzc3vDbzU4TXMhtjlXaEKJGOvK3f82i
treesuffix: $BASE_DN

# Access level
accessLevel: 100

# Login method
loginMethod: search
loginSearchSuffix: $BASE_DN
loginSearchFilter: (uid=%USER%)
loginSearchDN: 
loginSearchPassword: 
httpAuthentication: false

# Admins
Admins: $ADMIN_DN
admins: $ADMIN_DN

# Password policy
pwdPolicyMinLength: 0
pwdPolicyMinLowercase: 0
pwdPolicyMinUppercase: 0
pwdPolicyMinNumeric: 0
pwdPolicyMinSymbolic: 0
pwdPolicyMinClasses: 0

# Type settings
types: suffix_user: ou=users,$BASE_DN
types: suffix_group: ou=groups,$BASE_DN
types: suffix_smbDomain: $BASE_DN

# Active account types
activeTypes: user,group

# Modules for user type
modules: user_posixAccount
modules: user_inetOrgPerson
modules: user_shadowAccount

# Modules for group type  
modules: group_posixGroup

# Module settings - posixAccount
modules: posixAccount_minUID: 1000
modules: posixAccount_maxUID: 30000
modules: posixAccount_minMachine: 50000
modules: posixAccount_maxMachine: 60000
modules: posixAccount_pwdHash: SSHA
modules: posixAccount_shells: /bin/bash

# Module settings - posixGroup
modules: posixGroup_minGID: 10000
modules: posixGroup_maxGID: 20000
modules: posixGroup_pwdHash: SSHA

# Module settings - shadowAccount
modules: shadowAccount_shadowMin: 0
modules: shadowAccount_shadowMax: 999999
modules: shadowAccount_shadowWarning: 7
modules: shadowAccount_shadowInactive: -1
modules: shadowAccount_shadowExpire: 
modules: shadowAccount_shadowFlag: 0

# Job settings
jobsBindPassword: 
jobsBindUser: 
jobsDatabase: 
jobToken: 

# 2-factor authentication
twoFactorAuthentication: none
twoFactorAuthenticationURL: 
twoFactorAuthenticationInsecure: false
twoFactorAuthenticationLabel: 
twoFactorAuthenticationOptional: false
twoFactorAuthenticationCaption: 

# Self service
selfServiceProfile: default
lamProMailSubject: 
lamProMailText: 
lamProMailIsHTML: false
EOF

chown apache:apache /var/lib/ldap-account-manager/config/profiles/default.conf
chmod 600 /var/lib/ldap-account-manager/config/profiles/default.conf


# ========================
#  CONFIGURAR APACHE
# ========================
cat > /etc/httpd/conf.d/lam.conf << 'EOF'
Alias /lam /var/www/html/lam

<Directory /var/www/html/lam>
    Options FollowSymLinks
    AllowOverride All
    Require all granted

    <IfModule mod_php.c>
        php_value session.save_path /var/lib/ldap-account-manager/sess
        php_value include_path /var/www/html/lam:/var/www/html/lam/lib
    </IfModule>
</Directory>
EOF

# Configurar permisos SELinux si está activo
if command -v setenforce &> /dev/null; then
    setenforce 0 || true
fi

systemctl restart httpd


# ========================
#  PÁGINA DE INICIO
# ========================


# ========================
#  INFO FINAL
# ========================
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo ""
echo "=========================================="
echo "   LAM INSTALADO Y CONFIGURADO"
echo "=========================================="
echo "URL: http://$PUBLIC_IP/lam"
echo "Usuario LDAP: $ADMIN_DN"
echo "Contraseña LDAP: 1234"
echo ""
echo "Contraseña maestra LAM: lam"
echo "=========================================="
