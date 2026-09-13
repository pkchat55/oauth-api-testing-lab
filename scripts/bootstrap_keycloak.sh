#!/usr/bin/env bash
#
# Bootstraps the Keycloak realm/clients/role needed by this lab.
# Idempotent: safe to re-run against an already-configured Keycloak instance.
#
# Usage:
#   ./scripts/bootstrap_keycloak.sh
#
# Env overrides:
#   KEYCLOAK_URL, REALM, CLIENT_ID, CLIENT_ID_NOROLE, ROLE_NAME,
#   ACCESS_TOKEN_LIFESPAN, KC_ADMIN_USER, KC_ADMIN_PASS
#
# On success, prints shell `export` lines for CLIENT_ID, CLIENT_SECRET,
# CLIENT_ID_NOROLE and CLIENT_SECRET_NOROLE. Use like:
#   eval "$(./scripts/bootstrap_keycloak.sh)"

set -euo pipefail

KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
REALM="${REALM:-api-testing}"
CLIENT_ID="${CLIENT_ID:-api-automation-client}"
CLIENT_ID_NOROLE="${CLIENT_ID_NOROLE:-api-automation-client-norole}"
ROLE_NAME="${ROLE_NAME:-api-user}"
ACCESS_TOKEN_LIFESPAN="${ACCESS_TOKEN_LIFESPAN:-6}"
KC_ADMIN_USER="${KC_ADMIN_USER:-admin}"
KC_ADMIN_PASS="${KC_ADMIN_PASS:-admin}"

log() { echo "[bootstrap-keycloak] $*" >&2; }

log "Waiting for Keycloak at $KEYCLOAK_URL ..."
for _ in $(seq 1 60); do
  if curl -sf -o /dev/null "$KEYCLOAK_URL/realms/master/.well-known/openid-configuration"; then
    break
  fi
  sleep 2
done

admin_token() {
  curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
    -d "grant_type=password" -d "client_id=admin-cli" \
    -d "username=$KC_ADMIN_USER" -d "password=$KC_ADMIN_PASS" \
    | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])"
}

ADMIN_TOKEN=$(admin_token)

realm_exists() {
  curl -sf -o /dev/null -H "Authorization: Bearer $ADMIN_TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM"
}

if realm_exists; then
  log "Realm '$REALM' already exists, skipping creation."
else
  log "Creating realm '$REALM' ..."
  curl -sf -o /dev/null -X POST "$KEYCLOAK_URL/admin/realms" \
    -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
    -d "{\"realm\":\"$REALM\",\"enabled\":true}"
fi

get_client_uuid() {
  local client_id="$1"
  curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM/clients?clientId=$client_id" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print(d[0]['id'] if d else '')"
}

create_client() {
  local client_id="$1"
  local uuid
  uuid=$(get_client_uuid "$client_id")

  if [[ -n "$uuid" ]]; then
    log "Client '$client_id' already exists ($uuid), skipping creation."
    echo "$uuid"
    return
  fi

  log "Creating client '$client_id' ..."
  curl -sf -o /dev/null -X POST "$KEYCLOAK_URL/admin/realms/$REALM/clients" \
    -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
    -d "{
      \"clientId\": \"$client_id\",
      \"protocol\": \"openid-connect\",
      \"publicClient\": false,
      \"serviceAccountsEnabled\": true,
      \"standardFlowEnabled\": false,
      \"directAccessGrantsEnabled\": false,
      \"clientAuthenticatorType\": \"client-secret\",
      \"enabled\": true
    }"

  get_client_uuid "$client_id"
}

get_client_secret() {
  local uuid="$1"
  curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM/clients/$uuid/client-secret" \
    | python3 -c "import sys,json;print(json.load(sys.stdin)['value'])"
}

# --- Realm role used for role-based authorization checks ---
if curl -sf -o /dev/null -H "Authorization: Bearer $ADMIN_TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM/roles/$ROLE_NAME"; then
  log "Role '$ROLE_NAME' already exists, skipping creation."
else
  log "Creating realm role '$ROLE_NAME' ..."
  curl -sf -o /dev/null -X POST "$KEYCLOAK_URL/admin/realms/$REALM/roles" \
    -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
    -d "{\"name\":\"$ROLE_NAME\"}"
fi
ROLE_JSON=$(curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KEYCLOAK_URL/admin/realms/$REALM/roles/$ROLE_NAME")

# --- Client 1: has the role, short token lifespan (used for expiry tests) ---
CLIENT_UUID=$(create_client "$CLIENT_ID")
CLIENT_SECRET=$(get_client_secret "$CLIENT_UUID")

SA_USER_ID=$(curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KEYCLOAK_URL/admin/realms/$REALM/clients/$CLIENT_UUID/service-account-user" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")

CURRENT_ROLES=$(curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KEYCLOAK_URL/admin/realms/$REALM/users/$SA_USER_ID/role-mappings/realm")
if echo "$CURRENT_ROLES" | python3 -c "import sys,json;roles=json.load(sys.stdin);exit(0 if any(r['name']=='$ROLE_NAME' for r in roles) else 1)"; then
  log "Role '$ROLE_NAME' already assigned to '$CLIENT_ID' service account."
else
  log "Assigning role '$ROLE_NAME' to '$CLIENT_ID' service account ..."
  curl -sf -o /dev/null -X POST "$KEYCLOAK_URL/admin/realms/$REALM/users/$SA_USER_ID/role-mappings/realm" \
    -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
    -d "[$ROLE_JSON]"
fi

log "Setting access-token lifespan for '$CLIENT_ID' to ${ACCESS_TOKEN_LIFESPAN}s ..."
curl -sf -o /dev/null -X PUT "$KEYCLOAK_URL/admin/realms/$REALM/clients/$CLIENT_UUID" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d "{\"attributes\": {\"access.token.lifespan\": \"$ACCESS_TOKEN_LIFESPAN\"}}"

# --- Client 2: intentionally has no role (used for 403 tests) ---
CLIENT2_UUID=$(create_client "$CLIENT_ID_NOROLE")
CLIENT2_SECRET=$(get_client_secret "$CLIENT2_UUID")

log "Bootstrap complete."

echo "export CLIENT_ID='$CLIENT_ID'"
echo "export CLIENT_SECRET='$CLIENT_SECRET'"
echo "export CLIENT_ID_NOROLE='$CLIENT_ID_NOROLE'"
echo "export CLIENT_SECRET_NOROLE='$CLIENT2_SECRET'"
