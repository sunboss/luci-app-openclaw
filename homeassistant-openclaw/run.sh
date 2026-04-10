#!/usr/bin/with-contenv bashio
set -euo pipefail

readonly OPENCLAW_INSTALL="/opt/openclaw"
readonly OPENCLAW_GLOBAL="${OPENCLAW_INSTALL}/global"
readonly DATA_DIR="/data"
readonly STATE_DIR="${DATA_DIR}/.openclaw"
readonly CONFIG_FILE="${STATE_DIR}/openclaw.json"
readonly VERSION_MARKER="${STATE_DIR}/.doctor_ran_version"
readonly TOKEN_FILE="${DATA_DIR}/gateway_token.txt"
readonly GATEWAY_PORT="18789"
readonly INGRESS_PORT="8099"
readonly NGINX_CONFIG="/etc/nginx/http.d/openclaw.conf"

export PATH="${OPENCLAW_GLOBAL}/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="${DATA_DIR}"
export OPENCLAW_HOME="${DATA_DIR}"
export OPENCLAW_STATE_DIR="${STATE_DIR}"
export OPENCLAW_CONFIG_PATH="${CONFIG_FILE}"
export npm_config_cache="${DATA_DIR}/.npm"

NODE_BIN="$(command -v node)"
OPENCLAW_PID=""
NGINX_PID=""

find_oc_entry() {
    local search_dirs=(
        "${OPENCLAW_GLOBAL}/lib/node_modules/openclaw"
        "${OPENCLAW_GLOBAL}/node_modules/openclaw"
    )
    local dir

    for dir in "${search_dirs[@]}"; do
        if [[ -f "${dir}/openclaw.mjs" ]]; then
            printf '%s\n' "${dir}/openclaw.mjs"
            return 0
        fi
        if [[ -f "${dir}/dist/cli.js" ]]; then
            printf '%s\n' "${dir}/dist/cli.js"
            return 0
        fi
    done

    return 1
}

generate_token() {
    "${NODE_BIN}" -e "process.stdout.write(require('crypto').randomBytes(24).toString('hex'))"
}

normalize_token() {
    local token="$1"

    if [[ "${token}" =~ ^[A-Za-z0-9._~-]+$ ]]; then
        printf '%s\n' "${token}"
        return 0
    fi

    bashio::log.warning "Configured gateway_token contains unsupported characters; generating a safe token instead"
    generate_token
}

normalize_tools_profile() {
    local profile="$1"

    case "${profile}" in
        coding|messaging)
            printf '%s\n' "${profile}"
            ;;
        *)
            bashio::log.warning "Unsupported tools_profile '${profile}', falling back to 'coding'"
            printf '%s\n' "coding"
            ;;
    esac
}

patch_iframe_headers() {
    local dist_dir="${OPENCLAW_GLOBAL}/lib/node_modules/openclaw/dist"
    local patched=0
    local file=""

    if [[ ! -d "${dist_dir}" ]]; then
        return 0
    fi

    while IFS= read -r -d '' file; do
        if grep -q 'X-Frame-Options.*DENY\|frame-ancestors.*none' "${file}" 2>/dev/null; then
            sed -i 's|res\.setHeader("X-Frame-Options", "DENY")|res.setHeader("X-Frame-Options", "ALLOW-FROM *") // patched for Home Assistant ingress|g' "${file}"
            sed -i "s|\"frame-ancestors 'none'\"|\"frame-ancestors *\"|g" "${file}"
            patched=1
        fi
    done < <(find "${dist_dir}" -type f \( -name 'server.impl-*.js' -o -name 'gateway-cli-*.js' \) -print0 2>/dev/null)

    if [[ "${patched}" -eq 1 ]]; then
        bashio::log.info "Patched OpenClaw frame headers for Home Assistant ingress"
    fi
}

bootstrap_state() {
    local oc_entry="$1"
    local tools_profile="$2"

    mkdir -p "${STATE_DIR}" "${DATA_DIR}/.npm"

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        bashio::log.info "Initializing OpenClaw state in ${STATE_DIR}"
        "${NODE_BIN}" "${oc_entry}" onboard --non-interactive --accept-risk --tools-profile "${tools_profile}" >/dev/null 2>&1 || true
    fi
}

resolve_token() {
    local configured_token
    local existing_token

    configured_token="$(bashio::config 'gateway_token')"
    if [[ -n "${configured_token}" ]]; then
        printf '%s\n' "${configured_token}"
        return 0
    fi

    if [[ -f "${CONFIG_FILE}" ]]; then
        existing_token="$("${NODE_BIN}" -e "const fs=require('fs'); try { const d=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); process.stdout.write(d.gateway?.auth?.token || ''); } catch (error) {}" "${CONFIG_FILE}" 2>/dev/null || true)"
        if [[ -n "${existing_token}" ]]; then
            printf '%s\n' "${existing_token}"
            return 0
        fi
    fi

    generate_token
}

sync_config() {
    local token="$1"
    local tools_profile="$2"
    local disable_update_check="$3"

    OC_CONFIG_FILE="${CONFIG_FILE}" \
    OC_GATEWAY_PORT="${GATEWAY_PORT}" \
    OC_GATEWAY_TOKEN="${token}" \
    OC_TOOLS_PROFILE="${tools_profile}" \
    OC_DISABLE_UPDATE_CHECK="${disable_update_check}" \
    "${NODE_BIN}" <<'NODE'
const fs = require("fs");
const path = require("path");

const file = process.env.OC_CONFIG_FILE;
const port = Number.parseInt(process.env.OC_GATEWAY_PORT || "18789", 10);
const token = process.env.OC_GATEWAY_TOKEN || "";
const toolsProfile = process.env.OC_TOOLS_PROFILE || "coding";
const disableUpdateCheck = process.env.OC_DISABLE_UPDATE_CHECK === "true";

let data = {};

try {
  data = JSON.parse(fs.readFileSync(file, "utf8"));
} catch (error) {
  data = {};
}

data.gateway = data.gateway || {};
data.gateway.port = Number.isFinite(port) ? port : 18789;
data.gateway.bind = "loopback";
data.gateway.mode = "local";
data.gateway.controlUi = data.gateway.controlUi || {};
data.gateway.controlUi.allowInsecureAuth = true;
data.gateway.controlUi.dangerouslyDisableDeviceAuth = true;
data.gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback = true;
data.gateway.auth = data.gateway.auth || {};
data.gateway.auth.mode = "token";
data.gateway.auth.token = token;

delete data.gateway.name;
delete data.gateway.bonjour;
delete data.gateway.plugins;

data.acp = data.acp || {};
data.acp.dispatch = data.acp.dispatch || {};
data.acp.dispatch.enabled = false;

data.tools = data.tools || {};
data.tools.profile = toolsProfile;

data.update = data.update || {};
data.update.checkOnStart = !disableUpdateCheck ? true : false;

if (data.models?.providers?.ollama) {
  const ollama = data.models.providers.ollama;
  if (ollama.api === "openai-chat-completions" || ollama.api === "openai-completions") {
    ollama.api = "ollama";
  }
  if (typeof ollama.baseUrl === "string" && ollama.baseUrl.endsWith("/v1")) {
    ollama.baseUrl = ollama.baseUrl.replace(/\/v1$/, "");
  }
  if (ollama.apiKey === "ollama") {
    ollama.apiKey = "ollama-local";
  }
}

if (data.talk) {
  delete data.talk.voiceId;
  delete data.talk.apiKey;
}

if (data.browser?.ssrfPolicy) {
  delete data.browser.ssrfPolicy.allowPrivateNetwork;
}

if (data.hooks?.internal) {
  delete data.hooks.internal.handlers;
}

["channel", "group", "room"].forEach((key) => {
  if (!data[key] || typeof data[key] !== "object") {
    return;
  }
  Object.values(data[key]).forEach((entry) => {
    if (entry && Object.prototype.hasOwnProperty.call(entry, "allow")) {
      entry.enabled = entry.allow;
      delete entry.allow;
    }
  });
});

if (data.agents?.defaults) {
  delete data.agents.defaults.cliBackends;
}

data.plugins = data.plugins || {};
if (!Array.isArray(data.plugins.allow)) {
  data.plugins.allow = [];
}
if (!data.plugins.allow.includes("copilot-proxy")) {
  data.plugins.allow.push("copilot-proxy");
}
if (data.plugins.installs && typeof data.plugins.installs === "object") {
  Object.values(data.plugins.installs).forEach((install) => {
    if (!install || typeof install.installPath !== "string") {
      return;
    }
    const match = install.installPath.match(/\/([^/]+)\/?$/);
    if (match && match[1] && !data.plugins.allow.includes(match[1])) {
      data.plugins.allow.push(match[1]);
    }
  });
}

fs.mkdirSync(path.dirname(file), { recursive: true });
fs.writeFileSync(file, JSON.stringify(data, null, 2));
NODE
}

run_doctor_if_needed() {
    local oc_entry="$1"
    local current_version
    local last_version=""

    current_version="$("${NODE_BIN}" "${oc_entry}" --version 2>/dev/null | tr -d '[:space:]')"
    current_version="${current_version#v}"
    current_version="${current_version:-unknown}"

    if [[ -f "${VERSION_MARKER}" ]]; then
        last_version="$(tr -d '[:space:]' < "${VERSION_MARKER}")"
    fi

    if [[ "${current_version}" == "${last_version}" ]]; then
        return 0
    fi

    bashio::log.info "OpenClaw version changed (${last_version:-none} -> ${current_version}), running doctor --fix"
    "${NODE_BIN}" "${oc_entry}" doctor --fix >/dev/null 2>&1 || bashio::log.warning "doctor --fix exited non-zero; continuing with synced config"
    printf '%s\n' "${current_version}" > "${VERSION_MARKER}"
}

render_nginx_config() {
    local token="$1"

    cat > "${NGINX_CONFIG}" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen ${INGRESS_PORT};
    server_name _;
    client_max_body_size 64m;

    location = /health {
        access_log off;
        add_header Content-Type text/plain always;
        return 200 'ok';
    }

    location = / {
        if (\$cookie_openclaw_bootstrap != 1) {
            add_header Set-Cookie "openclaw_bootstrap=1; Max-Age=10; Path=/; HttpOnly; SameSite=Lax" always;
            return 302 /#token=${token};
        }

        proxy_pass http://127.0.0.1:${GATEWAY_PORT};
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_redirect off;
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
        proxy_hide_header X-Frame-Options;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Ingress-Path \$http_x_ingress_path;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }

    location / {
        proxy_pass http://127.0.0.1:${GATEWAY_PORT};
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_redirect off;
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
        proxy_hide_header X-Frame-Options;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Ingress-Path \$http_x_ingress_path;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }
}
EOF
}

cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM

    if [[ -n "${OPENCLAW_PID}" ]]; then
        kill "${OPENCLAW_PID}" >/dev/null 2>&1 || true
        wait "${OPENCLAW_PID}" >/dev/null 2>&1 || true
    fi

    if [[ -n "${NGINX_PID}" ]]; then
        kill "${NGINX_PID}" >/dev/null 2>&1 || true
        wait "${NGINX_PID}" >/dev/null 2>&1 || true
    fi

    exit "${exit_code}"
}

main() {
    local oc_entry
    local token
    local tools_profile
    local disable_update_check="false"

    oc_entry="$(find_oc_entry || true)"
    if [[ -z "${oc_entry}" ]]; then
        bashio::log.fatal "Unable to find OpenClaw entrypoint under ${OPENCLAW_GLOBAL}"
        exit 1
    fi

    if bashio::config.true 'disable_update_check'; then
        disable_update_check="true"
    fi
    tools_profile="$(normalize_tools_profile "$(bashio::config 'tools_profile')")"

    bootstrap_state "${oc_entry}" "${tools_profile}"
    token="$(normalize_token "$(resolve_token)")"
    sync_config "${token}" "${tools_profile}" "${disable_update_check}"
    run_doctor_if_needed "${oc_entry}"
    sync_config "${token}" "${tools_profile}" "${disable_update_check}"
    patch_iframe_headers
    render_nginx_config "${token}"
    printf '%s\n' "${token}" > "${TOKEN_FILE}"
    chmod 600 "${TOKEN_FILE}" 2>/dev/null || true

    bashio::log.info "OpenClaw token: ${token}"
    bashio::log.info "Gateway token persisted to ${TOKEN_FILE}"
    bashio::log.info "Starting OpenClaw gateway on 127.0.0.1:${GATEWAY_PORT}"

    trap cleanup EXIT INT TERM

    nginx -t
    nginx -g 'daemon off;' &
    NGINX_PID="$!"

    "${NODE_BIN}" "${oc_entry}" gateway run --port "${GATEWAY_PORT}" --bind loopback &
    OPENCLAW_PID="$!"

    wait -n "${NGINX_PID}" "${OPENCLAW_PID}"
}

main "$@"
