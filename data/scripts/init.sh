#!/usr/bin/env bash
set -euo pipefail

# ensure Bash and version for mapfile/process substitution
: "${BASH_VERSION:?run with bash}"
if (( BASH_VERSINFO[0] < 4 )); then
  echo "Need Bash >= 4" >&2
  exit 2
fi

DATA_PATH="./data"
MOUNTED_PATH="./mounted"
ASSETS_PATH="${DATA_PATH}/assets"
TMP_PATH="${DATA_PATH}/tmp"

JENKINS_BASEURL=http://localhost:8088
JENKINS_USERNAME=admin
JENKINS_API_TOKEN=$(<"${MOUNTED_PATH}/jenkins_home/api_token.txt")
JENKINS_CLI_DEST="${TMP_PATH}/jenkins-cli.jar"
JENKINS_CLI_URL="${JENKINS_BASEURL}/jnlpJars/jenkins-cli.jar"
JENKINS_WANTED_PLUGINS_FILE="${ASSETS_PATH}/plugins.txt"
JENKINS_WANTED_PLUGINS=$(<"${JENKINS_WANTED_PLUGINS_FILE}")

NEXUS_BASEURL=http://localhost:8888
NEXUS_ADMIN_USERNAME=admin
NEXUS_ADMIN_PASSWORD=admin
NEXUS_WILL_BE_REMOVED_REGS=(
    # Maven
    maven-public
    maven-central
    maven-releases
    maven-snapshots

    # NuGet (if they exist in your instance)
    nuget-group
    nuget.org-proxy
    nuget-hosted
    nuget.org
)

ensureCache() {
    [ -d "$TMP_PATH" ] || mkdir -p "$TMP_PATH"
    chmod +w "$TMP_PATH"
}

waitForService() {
    local SERVICE_NAME=$1
    local SERVICE_URL=$2

    echo "⏳ Waiting for ${SERVICE_NAME} to be ready..."
    
    while true; do
        http_status=$(curl -s -o /dev/null -w "%{http_code}" "${SERVICE_URL}")
        
        if [[ "$http_status" == "200" ]]; then
            echo "✅ ${SERVICE_NAME} is ready (HTTP 200)."
            break
        else
            echo "❌ ${SERVICE_NAME} not ready yet (status: $http_status), retrying in 5s..."
            sleep 5
        fi
    done
}

waitForJenkins () {
    waitForService "Jenkins" "${JENKINS_BASEURL}/login"
}

downloadJenkinsCLI() {
    echo "⬇️ Downloading fresh Jenkins CLI from $JENKINS_CLI_URL ..."

    local tmp="${JENKINS_CLI_DEST}.tmp.$$"
    local auth=()
    [ -n "${JENKINS_USERNAME:-}" ] && [ -n "${JENKINS_API_TOKEN:-}" ] && auth=(-u "$JENKINS_USERNAME:$JENKINS_API_TOKEN")

    # download with retries, follow redirects
    if ! curl -fSL --retry 3 --retry-all-errors --connect-timeout 10 --max-time 120 \
            "${auth[@]}" -o "$tmp" "$JENKINS_CLI_URL"; then
        rm -f "$tmp"
        echo "download failed: $JENKINS_CLI_URL" >&2
        return 1
    fi

    # sanity check: jar magic
    if ! head -c 4 "$tmp" | cmp -s - <(printf 'PK\003\004'); then
        echo "not a jar (got $(file -b "$tmp" 2>/dev/null))" >&2
        rm -f "$tmp"
        return 2
    fi

    # atomic replace only if changed
    if [ -s "$JENKINS_CLI_DEST" ] && cmp -s "$tmp" "$JENKINS_CLI_DEST"; then
        rm -f "$tmp"
        echo "✅ Jenkins CLI up to date: $JENKINS_CLI_DEST"
    else
        mv -f "$tmp" "$JENKINS_CLI_DEST"
        chmod 0644 "$JENKINS_CLI_DEST" || true
        echo "✅ Jenkins CLI saved: $JENKINS_CLI_DEST"
    fi

    # print version if java exists
    if command -v java >/dev/null 2>&1; then
        echo -n "🔎 CLI version: "
        java -jar "$JENKINS_CLI_DEST" -s "$JENKINS_BASEURL" -auth "$JENKINS_USERNAME:$JENKINS_API_TOKEN" -version || true
    fi
}

testJenkinsAPIToken() {
  echo "🔐 Verifying API token via /whoAmI ..."
  resp=$(curl -fsS -u "$JENKINS_USERNAME:$JENKINS_API_TOKEN" "$JENKINS_BASEURL/whoAmI/api/json" || true)
  if [[ -z "$resp" ]]; then
    echo "❌ Failed to contact Jenkins /whoAmI"; exit 1
  fi

  if command -v jq >/dev/null 2>&1; then
    auth=$(jq -r '.authenticated' <<<"$resp" 2>/dev/null || echo "false")
    name=$(jq -r '.name' <<<"$resp" 2>/dev/null || echo "")
  else
    auth=$(grep -o '"authenticated":[^,]*' <<<"$resp" | cut -d: -f2 | tr -d ' "' || echo "")
    name=$(grep -o '"name":"[^"]*"' <<<"$resp" | cut -d: -f2 | tr -d '"' || echo "")
  fi

  if [[ "$auth" == "true" && "$name" == "$JENKINS_USERNAME" ]]; then
    echo "✅ Token OK for user '$name'."
  else
    echo "❌ Token invalid or wrong user. Response: $resp"
    exit 1
  fi
}

installJenkinsPlugins() {
  echo "📦 Installing plugins from ${JENKINS_WANTED_PLUGINS_FILE}"

  # Build arg list from JENKINS_WANTED_PLUGINS (strip comments/blank lines)
  mapfile -t plugins < <(printf "%s\n" "$JENKINS_WANTED_PLUGINS" \
    | sed 's/#.*//' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | awk 'NF>0')

  if [[ ${#plugins[@]} -eq 0 ]]; then
    echo "ℹ️ No plugins to install."
    return
  fi

  echo "➡️  ${plugins[*]}"
  # -deploy installs and loads without requiring manual restart
  java -jar "$JENKINS_CLI_DEST" -s "$JENKINS_BASEURL" -auth "$JENKINS_USERNAME:$JENKINS_API_TOKEN" \
    install-plugin -deploy "${plugins[@]}"
  echo "✅ install-plugin requested."
}

waitForJenkinsPluginsInstalled() {
  echo "⏳ Verifying plugins are installed..."

  # Collect desired plugin IDs (ignore versions if provided as id:version)
  mapfile -t want_ids < <(printf "%s\n" "$JENKINS_WANTED_PLUGINS" \
    | sed 's/#.*//' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | awk 'NF>0' \
    | awk -F: '{print $1}')

  # Poll until all appear in list-plugins
  while true; do
    list=$(java -jar "$JENKINS_CLI_DEST" -s "$JENKINS_BASEURL" -auth "$JENKINS_USERNAME:$JENKINS_API_TOKEN" list-plugins || true)
    all_ok=true
    for pid in "${want_ids[@]}"; do
      if ! grep -qE "^${pid}[[:space:]]" <<< "$list"; then
        echo "❌ Missing: $pid"
        all_ok=false
      fi
    done
    if $all_ok; then
      echo "✅ All requested plugins are present."
      break
    fi
    echo "…retrying in 5s"
    sleep 5
  done
}

restartJenkins() {
  echo "🔄 Safe-restarting Jenkins…"
  java -jar "$JENKINS_CLI_DEST" -s "$JENKINS_BASEURL" -auth "$JENKINS_USERNAME:$JENKINS_API_TOKEN" safe-restart || true

  # Give it a moment to drop, then wait until it’s back
  sleep 3
  waitForJenkins
  echo "✅ Jenkins restarted and ready."
}

waitForNexus() {
    waitForService "Nexus" "${NEXUS_BASEURL}/service/rest/v1/status/writable"
}

initNexusPassword() {
    local DEFAULT_PW=$(docker exec -it nexus cat /nexus-data/admin.password)
    local code
    echo "Default password: ${DEFAULT_PW}"
    code=$(curl -sf -u admin:"$DEFAULT_PW" \
        -H 'Content-Type: text/plain' \
        --data "${NEXUS_ADMIN_PASSWORD:?set it}" \
        -X PUT "$NEXUS_BASEURL/service/rest/v1/security/users/admin/change-password")

    echo "Change password response code: ${code}"
}

removeNexusRegistry() {
    local HEADER=(-H "X-Requested-By: nexus-cleanup")
    local name="$1"
    local url="$NEXUS_BASEURL/service/rest/v1/repositories/$name"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -u "$NEXUS_ADMIN_USERNAME:$NEXUS_ADMIN_PASSWORD" "${header[@]}" -X DELETE "$url" || true)

    case "$code" in
        204) echo "✓ Deleted: $name" ;;
        404) echo "• Not found (skipped): $name" ;;
        409) echo "✗ Conflict: $name (likely in use or member of a group). Try removing from groups first." ;;
        401|403) echo "✗ Auth/perm issue deleting $name (HTTP $code). Check credentials/roles." ;;
        *)   echo "✗ HTTP $code deleting $name" ;;
    esac
}

removeDefaultRegistries() {
    echo "🗑️ Removing default registries..."
    for r in "${NEXUS_WILL_BE_REMOVED_REGS[@]}"; do
        echo "👋 $r"
        removeNexusRegistry "$r"
    done
}

addNPMRegistry() {
  local NAME="${1:-npmjs}"
  local REMOTE_URL="${2:-https://registry.npmjs.org}"
  local BLOB="${3:-default}"

  local BASE="$NEXUS_BASEURL/service/rest/v1/repositories"
  local GET_URL="$BASE/$NAME"
  local POST_URL="$BASE/npm/proxy"
  local PUT_URL="$BASE/npm/proxy/$NAME"

  # Payload
  local BODY
  BODY=$(cat <<JSON
{
  "name": "$NAME",
  "online": true,
  "storage": {
    "blobStoreName": "$BLOB",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "$REMOTE_URL",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {
    "blocked": false,
    "autoBlock": true,
    "connection": {
      "retries": 3,
      "userAgentSuffix": "nexus-bootstrap",
      "timeout": 30,
      "enableCircularRedirects": false,
      "enableCookies": false
    }
  },
  "routingRuleName": null
}
JSON
)

  # Exists?
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -u "$NEXUS_ADMIN_USERNAME:$NEXUS_ADMIN_PASSWORD" \
    "${header[@]}" "$GET_URL" || true)

  if [[ "$code" == "200" ]]; then
    # Update
    code=$(curl -s -o /dev/null -w "%{http_code}" -u "$NEXUS_ADMIN_USERNAME:$NEXUS_ADMIN_PASSWORD" \
      "${header[@]}" -H "Content-Type: application/json" \
      -X PUT "$PUT_URL" -d "$BODY" || true)
    case "$code" in
      204) echo "✓ Updated npm proxy: $NAME → $REMOTE_URL (blob: $BLOB)";;
      400) echo "✗ Update failed (400). Check payload."; exit 1;;
      401|403) echo "✗ Update forbidden (HTTP $code). Check credentials/roles."; exit 1;;
      *) echo "✗ Update failed (HTTP $code)."; exit 1;;
    esac
  elif [[ "$code" == "404" ]]; then
    # Create
    code=$(curl -s -o /dev/null -w "%{http_code}" -u "$NEXUS_ADMIN_USERNAME:$NEXUS_ADMIN_PASSWORD" \
      "${header[@]}" -H "Content-Type: application/json" \
      -X POST "$POST_URL" -d "$BODY" || true)
    case "$code" in
      201) echo "✓ Created npm proxy: $NAME → $REMOTE_URL (blob: $BLOB)";;
      400) echo "✗ Create failed (400). Check payload."; exit 1;;
      401|403) echo "✗ Create forbidden (HTTP $code). Check credentials/roles."; exit 1;;
      409) echo "• Already exists (409): $NAME";;
      *) echo "✗ Create failed (HTTP $code)."; exit 1;;
    esac
  else
    echo "✗ Unexpected GET status for $NAME: HTTP $code"
    exit 1
  fi
}

addDockerProxy() {
  local NAME="${1:-docker-proxy}"
  local REMOTE_URL="${2:-https://registry-1.docker.io}"
  local BLOB="${3:-default}"
  # index type: HUB | REGISTRY | CUSTOM  (HUB = Use Docker Hub)
  local INDEX_TYPE="${4:-HUB}"
  # only used when INDEX_TYPE=CUSTOM
  local INDEX_URL="${5:-}"

  local BASE="$NEXUS_BASEURL/service/rest/v1/repositories"
  local GET_URL="$BASE/$NAME"
  local POST_URL="$BASE/docker/proxy"
  local PUT_URL="$BASE/docker/proxy/$NAME"

  # JSON payload
  local BODY
  BODY=$(cat <<JSON
{
  "name": "$NAME",
  "online": true,
  "storage": {
    "blobStoreName": "$BLOB",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "$REMOTE_URL",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {
    "blocked": false,
    "autoBlock": true,
    "connection": {
      "retries": 3,
      "userAgentSuffix": "nexus-bootstrap",
      "timeout": 30,
      "enableCircularRedirects": false,
      "enableCookies": false
    }
  },
  "docker": {
    "v1Enabled": false,
    "forceBasicAuth": true,
    "httpPort": null,
    "httpsPort": null
  },
  "dockerProxy": {
    "indexType": "$INDEX_TYPE"$( [[ "$INDEX_TYPE" == "CUSTOM" ]] && printf ', "indexUrl": "%s"' "$INDEX_URL" )
  },
  "routingRuleName": null
}
JSON
)

  # Exists?
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -u "$NEXUS_ADMIN_USERNAME:$NEXUS_ADMIN_PASSWORD" \
    "${header[@]}" "$GET_URL" || true)

  if [[ "$code" == "200" ]]; then
    # Update
    code=$(curl -s -o /dev/null -w "%{http_code}" -u "$NEXUS_ADMIN_USERNAME:$NEXUS_ADMIN_PASSWORD" \
      "${header[@]}" -H "Content-Type: application/json" \
      -X PUT "$PUT_URL" -d "$BODY" || true)
    case "$code" in
      204) echo "✓ Updated docker proxy: $NAME → $REMOTE_URL (blob: $BLOB, index: $INDEX_TYPE)";;
      400) echo "✗ Update failed (400). Check payload."; exit 1;;
      401|403) echo "✗ Update forbidden (HTTP $code). Check credentials/roles."; exit 1;;
      *) echo "✗ Update failed (HTTP $code)."; exit 1;;
    esac
  elif [[ "$code" == "404" ]]; then
    # Create
    code=$(curl -s -o /dev/null -w "%{http_code}" -u "$NEXUS_ADMIN_USERNAME:$NEXUS_ADMIN_PASSWORD" \
      "${header[@]}" -H "Content-Type: application/json" \
      -X POST "$POST_URL" -d "$BODY" || true)
    case "$code" in
      201) echo "✓ Created docker proxy: $NAME → $REMOTE_URL (blob: $BLOB, index: $INDEX_TYPE)";;
      400) echo "✗ Create failed (400). Check payload."; exit 1;;
      401|403) echo "✗ Create forbidden (HTTP $code). Check credentials/roles."; exit 1;;
      409) echo "• Already exists (409): $NAME";;
      *) echo "✗ Create failed (HTTP $code)."; exit 1;;
    esac
  else
    echo "✗ Unexpected GET status for $NAME: HTTP $code"
    exit 1
  fi
}


# Ensure things
ensureCache

# Init Jenkins
# waitForJenkins
# restartJenkins
# downloadJenkinsCLI
# testJenkinsAPIToken
# installJenkinsPlugins
# waitForJenkinsPluginsInstalled
# restartJenkins

# Init Nexus
waitForNexus
initNexusPassword
removeDefaultRegistries
addNPMRegistry "npm-proxy"
addDockerProxy "docker-proxy"
