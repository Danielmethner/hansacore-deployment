# Keycloak with the HansaCore login and email theme baked in.
# Built by scripts/build-images.sh keycloak -> hansacore-keycloak:local.
FROM quay.io/keycloak/keycloak:24.0 AS builder

# Build-time options must match 02-keycloak.yaml, otherwise `kc.sh start`
# re-augments on every boot.
ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=false

# Keycloak runs as uid 1000. Own the theme explicitly and make it readable,
# otherwise it depends on the umask of whichever machine builds the image and
# Keycloak fails with "Template not found" (permission denied) at login.
COPY --chown=1000:0 themes/hansacore /opt/keycloak/themes/hansacore
RUN chmod -R u+rwX,go+rX /opt/keycloak/themes/hansacore \
 && /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:24.0
COPY --from=builder /opt/keycloak/ /opt/keycloak/
