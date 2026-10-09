#!/bin/sh
# Render slapd.conf with the admin password hash, then run slapd in the
# foreground on :1389 as the current (OpenShift-assigned) UID.
set -eu
: "${LDAP_ADMIN_PASSWORD:?LDAP_ADMIN_PASSWORD is required}"

hash=$(slappasswd -h '{SSHA}' -s "$LDAP_ADMIN_PASSWORD")
sed "s|@ROOTPW@|$hash|" /etc/sg-ldap/slapd.conf.tmpl >/etc/sg-ldap/slapd.conf
chmod 0640 /etc/sg-ldap/slapd.conf

slaptest -u -f /etc/sg-ldap/slapd.conf >/dev/null
echo "sg-ldap: starting slapd on :1389 as uid $(id -u)"
exec /usr/sbin/slapd -d stats -h "ldap://0.0.0.0:1389/" -f /etc/sg-ldap/slapd.conf
