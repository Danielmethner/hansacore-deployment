# Keycloak with the HansaCore login and email theme baked in.
# Built by scripts/build-images.sh keycloak -> hansacore-keycloak:local.
FROM quay.io/keycloak/keycloak:24.0 AS builder

# Build-time options must match 02-keycloak.yaml, otherwise `kc.sh start`
# re-augments on every boot.
ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=false

COPY themes/hansacore /opt/keycloak/themes/hansacore
RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:24.0
COPY --from=builder /opt/keycloak/ /opt/keycloak/
