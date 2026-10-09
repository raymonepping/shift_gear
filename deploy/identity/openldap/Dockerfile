# Shift Gear OpenLDAP — Alpine's maintained OpenLDAP, built in-cluster.
#
# Why not an off-the-shelf image: CRC is arm64 with no emulation and runs
# workloads under SCC restricted-v2 (random UID, no root). osixia/openldap
# runs as root; Bitnami's free images are frozen (bitnamilegacy). This image
# runs slapd as whatever UID OpenShift assigns, on port 1389, with group 0
# owning every writable path (the OpenShift arbitrary-UID convention).
FROM docker.io/library/alpine:3.22

RUN apk add --no-cache openldap openldap-back-mdb openldap-clients && \
    mkdir -p /var/lib/openldap/data /var/lib/openldap/run /etc/sg-ldap && \
    chgrp -R 0 /var/lib/openldap /etc/openldap /etc/sg-ldap && \
    chmod -R g=u /var/lib/openldap /etc/openldap /etc/sg-ldap

COPY slapd.conf.tmpl entrypoint.sh /etc/sg-ldap/
RUN chmod 0775 /etc/sg-ldap/entrypoint.sh

USER 1001
EXPOSE 1389
ENTRYPOINT ["/etc/sg-ldap/entrypoint.sh"]
