#!/bin/bash
set -euo pipefail

LOGFILE_DEFAULT="/var/log/elasticsearch-setup.log"
if [ -w "$LOGFILE_DEFAULT" ] || [ -w "$(dirname "$LOGFILE_DEFAULT")" ]; then
    LOGFILE="$LOGFILE_DEFAULT"
else
    LOGFILE="/tmp/elasticsearch-setup.log"
fi
exec > >(tee -a "$LOGFILE") 2>&1
trap 'echo "[$(date)] [ERR] ERROR on line $LINENO (exit code: $?)" >&2' ERR
trap 'echo "[$(date)] Script exited with code $? at line $LINENO" >&2' EXIT

echo "===== Elasticsearch Setup Script ====="
echo "Timestamp: $(date)"
echo "User: $(whoami)"
echo "Hostname: $(hostname -f)"
echo "Shell: $SHELL"
echo "Working Dir: $(pwd)"
echo "Script: $0"
echo "======================================"
echo ""

CERT_DIR="/etc/elasticsearch/certs"
CERT_FILE="${CERT_DIR}/elastic-certificates.p12"
ES_CONFIG="/etc/elasticsearch/elasticsearch.yml"
DATA_DIR="/var/lib/elasticsearch"
NODE_IP_HOSTNAME="$(hostname -f)"
NODE_IP="$(hostname -I | awk '{print $1}')"
ELASTIC_VERSION="8.19.16"
FIREWALL_ENABLED=true
RESET_ELASTIC_PASSWORD="${RESET_ELASTIC_PASSWORD:-false}"
FRESH_INSTALL=false
NODE_CERT="${CERT_DIR}/${NODE_IP_HOSTNAME}/${NODE_IP_HOSTNAME}.crt"
NODE_KEY="${CERT_DIR}/${NODE_IP_HOSTNAME}/${NODE_IP_HOSTNAME}.key"
WUG_USER="${WUG_USER:-wug_user}"
WUG_USER_PASSWORD="${WUG_USER_PASSWORD:-}"  # leave blank to auto-generate

echo "[PKG] Elasticsearch $ELASTIC_VERSION Installation and Configuration"
echo "--> Node IP: $NODE_IP"
echo "--> Hostname: $NODE_IP_HOSTNAME"
echo "----------------------------------------"

echo "[AUTH] Validating sudo access..."
SUDO="sudo"
if sudo -n true 2>/dev/null; then
    SUDO="sudo -n"
elif [ -t 0 ]; then
    sudo -v
else
    echo "[ERR] sudo requires a password, but no TTY is available."
    echo "--> Re-run with a tty: ssh -t elasticsearch2 '/home/jason/install-elastic.sh'"
    exit 1
fi
echo "[OK] Sudo access confirmed."

echo "[STOP] Stopping Elasticsearch if running..."
$SUDO systemctl stop elasticsearch 2>/dev/null || echo "[INFO] Elasticsearch was not running."
echo "[OK] Elasticsearch stopped (if it was running)."

# Detect package manager and architecture
if command -v dnf &>/dev/null; then
    PKG_MGR=dnf
elif command -v yum &>/dev/null; then
    PKG_MGR=yum
elif command -v apt-get &>/dev/null; then
    PKG_MGR=apt
else
    echo "[ERR] No supported package manager found (dnf/yum/apt-get)."
    exit 1
fi
ARCH="$(uname -m)"
# Map uname arch to package arch suffixes
if [ "$ARCH" = "aarch64" ]; then
    RPM_ARCH="aarch64"
    DEB_ARCH="arm64"
else
    RPM_ARCH="x86_64"
    DEB_ARCH="amd64"
fi
echo "--> Package manager: $PKG_MGR | Arch: $ARCH"

# ---------------------------------------------------------------------------
# Dependency bootstrap — install any missing tools before we need them
# ---------------------------------------------------------------------------
REQUIRED_CMDS=(curl unzip awk)
MISSING_PKGS=()

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "[DEP] '$cmd' not found — queuing for install..."
        MISSING_PKGS+=("$cmd")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "[DEP] Installing missing dependencies: ${MISSING_PKGS[*]}"
    if [ "$PKG_MGR" = "apt" ]; then
        $SUDO apt-get update -q
        $SUDO apt-get install -y "${MISSING_PKGS[@]}"
    else
        $SUDO "$PKG_MGR" install -y "${MISSING_PKGS[@]}"
    fi
    echo "[OK] Dependencies installed."
else
    echo "[OK] All required dependencies already present."
fi
# ---------------------------------------------------------------------------

echo "[GET] Checking Elasticsearch installation..."
INSTALLED_VER=""
if [ "$PKG_MGR" = "apt" ]; then
    INSTALLED_VER="$(dpkg-query -W -f='${Version}' elasticsearch 2>/dev/null | cut -d- -f1 || true)"
else
    INSTALLED_VER="$(rpm -q elasticsearch --queryformat '%{VERSION}' 2>/dev/null || true)"
fi

if [ "$INSTALLED_VER" = "$ELASTIC_VERSION" ]; then
    echo "[OK] Elasticsearch $ELASTIC_VERSION is already installed at target version. Skipping install."
elif [ -n "$INSTALLED_VER" ]; then
    echo "--> Upgrading Elasticsearch from $INSTALLED_VER --> $ELASTIC_VERSION..."
    if [ "$PKG_MGR" = "apt" ]; then
        ES_DEB_URL="https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${ELASTIC_VERSION}-${DEB_ARCH}.deb"
        TMP_DEB="/tmp/elasticsearch-${ELASTIC_VERSION}.deb"
        curl -fsSL "$ES_DEB_URL" -o "$TMP_DEB"
        $SUDO dpkg -i "$TMP_DEB"
        rm -f "$TMP_DEB"
    else
        ES_RPM_URL="https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${ELASTIC_VERSION}-${RPM_ARCH}.rpm"
        $SUDO $PKG_MGR upgrade -y "$ES_RPM_URL" 2>/dev/null || \
            $SUDO $PKG_MGR install -y "$ES_RPM_URL"
    fi
    echo "[OK] Elasticsearch upgraded to $ELASTIC_VERSION."
    FRESH_INSTALL=true
else
    echo "--> Installing Elasticsearch $ELASTIC_VERSION..."
    if [ "$PKG_MGR" = "apt" ]; then
        ES_DEB_URL="https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${ELASTIC_VERSION}-${DEB_ARCH}.deb"
        TMP_DEB="/tmp/elasticsearch-${ELASTIC_VERSION}.deb"
        curl -fsSL "$ES_DEB_URL" -o "$TMP_DEB"
        $SUDO dpkg -i "$TMP_DEB"
        rm -f "$TMP_DEB"
    else
        ES_RPM_URL="https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${ELASTIC_VERSION}-${RPM_ARCH}.rpm"
        $SUDO $PKG_MGR install -y "$ES_RPM_URL"
    fi
    echo "[OK] Elasticsearch $ELASTIC_VERSION installed."
    FRESH_INSTALL=true
fi

echo "[CLEAN] Ensuring certificate directory is fresh..."
$SUDO rm -rf "$CERT_DIR"
$SUDO mkdir -p "$CERT_DIR"

echo "[CERT] Generating passwordless CA certificate in PEM format..."
$SUDO /usr/share/elasticsearch/bin/elasticsearch-certutil ca --pem --out "$CERT_DIR"/ca.zip --silent < /dev/null
$SUDO unzip -u -o "$CERT_DIR"/ca.zip -d "$CERT_DIR"/ca
$SUDO chown -R elasticsearch:elasticsearch "$CERT_DIR"/ca
$SUDO find "$CERT_DIR/ca" -type d -exec chmod 700 {} \;
$SUDO find "$CERT_DIR/ca" -type f -exec chmod 600 {} \;
$SUDO rm -f "$CERT_DIR"/ca.zip

CA_CERT="$CERT_DIR/ca/ca/ca.crt"
CA_KEY="$CERT_DIR/ca/ca/ca.key"

cat <<EOF > /tmp/elastic-certs.yml
instances:
  - name: $NODE_IP_HOSTNAME
    dns:
      - $NODE_IP_HOSTNAME
      - localhost
    ip:
      - $NODE_IP
      - 127.0.0.1
      - ::1
EOF

echo "[CERT] Generating passwordless node certificate in PEM format (with SANs)..."
$SUDO /usr/share/elasticsearch/bin/elasticsearch-certutil cert --silent \
    --pem --in /tmp/elastic-certs.yml \
    --ca-cert "$CA_CERT" \
    --ca-key "$CA_KEY" \
    --out "$CERT_DIR"/elastic-certs.zip < /dev/null

$SUDO unzip -u -o "$CERT_DIR"/elastic-certs.zip -d "$CERT_DIR"
$SUDO chown -R elasticsearch:elasticsearch "$CERT_DIR"
$SUDO find "$CERT_DIR" -type d -exec chmod 700 {} \;
$SUDO find "$CERT_DIR" -type f -exec chmod 600 {} \;
$SUDO rm -f "$CERT_DIR"/elastic-certs.zip

$SUDO rm -f /tmp/elastic-certs.yml
$SUDO chown elasticsearch:elasticsearch "$NODE_CERT" "$NODE_KEY" "$CA_CERT"
$SUDO chmod 600 "$NODE_CERT" "$NODE_KEY"
$SUDO chmod 644 "$CA_CERT"

echo "[OK] Node PEM cert/key and CA created fresh, SANs correct, permissions correct."

echo "[CONF] Writing new Elasticsearch configuration file..."
cat <<EOF | $SUDO tee "$ES_CONFIG" > /dev/null
# --- Network ---
network.host: 0.0.0.0
network.publish_host: $NODE_IP

# --- Cluster Bootstrap (safe for single node) ---
cluster.initial_master_nodes: ["$NODE_IP_HOSTNAME"]

# --- Security / SSL ---
xpack.security.enabled: true
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.certificate: "$NODE_CERT"
xpack.security.http.ssl.key: "$NODE_KEY"
xpack.security.http.ssl.certificate_authorities: ["$CA_CERT"]
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.certificate: "$NODE_CERT"
xpack.security.transport.ssl.key: "$NODE_KEY"
xpack.security.transport.ssl.certificate_authorities: ["$CA_CERT"]
xpack.security.authc.token.enabled: true

# --- Paths ---
path.logs: /var/log/elasticsearch
path.data: /var/lib/elasticsearch
EOF

echo "[OK] Elasticsearch config written."

echo "[CLEANUP] SSL keystore password cleanup not required (PEM-based TLS config)."

if [ "$FIREWALL_ENABLED" = true ]; then
    if $SUDO systemctl is-active --quiet firewalld 2>/dev/null; then
        # RHEL / Rocky / AlmaLinux / Fedora -- firewalld
        PRIMARY_IFACE="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
        FW_ZONE=""
        if [ -n "$PRIMARY_IFACE" ]; then
            FW_ZONE="$($SUDO firewall-cmd --get-zone-of-interface="$PRIMARY_IFACE" 2>/dev/null || true)"
        fi
        if [ -z "$FW_ZONE" ] || [ "$FW_ZONE" = "no zone" ]; then
            FW_ZONE="$($SUDO firewall-cmd --get-default-zone)"
        fi
        echo "[FW] firewalld detected -- opening ports 9200/9300 in zone '$FW_ZONE'..."
        $SUDO firewall-cmd --zone="$FW_ZONE" --add-port=9200/tcp 2>/dev/null || true
        $SUDO firewall-cmd --zone="$FW_ZONE" --add-port=9300/tcp 2>/dev/null || true
        $SUDO firewall-cmd --zone="$FW_ZONE" --add-port=9200/tcp --permanent
        $SUDO firewall-cmd --zone="$FW_ZONE" --add-port=9300/tcp --permanent
        $SUDO firewall-cmd --reload
        echo "[OK] firewalld rules applied (9200, 9300)."

    elif command -v ufw &>/dev/null && $SUDO ufw status 2>/dev/null | grep -q "Status: active"; then
        # Debian / Ubuntu -- ufw
        echo "[FW] ufw detected -- opening ports 9200/9300..."
        $SUDO ufw allow 9200/tcp
        $SUDO ufw allow 9300/tcp
        echo "[OK] ufw rules applied (9200, 9300)."

    elif command -v iptables &>/dev/null; then
        # Fallback -- raw iptables
        echo "[FW] iptables detected -- opening ports 9200/9300..."
        $SUDO iptables -C INPUT -p tcp --dport 9200 -j ACCEPT 2>/dev/null || \
            $SUDO iptables -A INPUT -p tcp --dport 9200 -j ACCEPT
        $SUDO iptables -C INPUT -p tcp --dport 9300 -j ACCEPT 2>/dev/null || \
            $SUDO iptables -A INPUT -p tcp --dport 9300 -j ACCEPT
        # Persist if iptables-save is available
        if command -v iptables-save &>/dev/null; then
            if [ -d /etc/iptables ]; then
                $SUDO iptables-save | $SUDO tee /etc/iptables/rules.v4 > /dev/null
            elif command -v service &>/dev/null && service iptables save &>/dev/null 2>&1; then
                true
            fi
        fi
        echo "[OK] iptables rules applied (9200, 9300)."
    else
        echo "[INFO] No supported firewall detected; skipping firewall changes."
    fi
fi

echo "[START] Starting Elasticsearch service..."
$SUDO systemctl enable elasticsearch
$SUDO systemctl start elasticsearch

echo "[WAIT] Waiting for Elasticsearch to be healthy..."
MAX_WAIT=60
wait_time=0
until {
    http_code="$(curl -sk -o /dev/null -w "%{http_code}" "https://$NODE_IP:9200" 2>/dev/null || true)"
    [ "$http_code" = "200" ] || [ "$http_code" = "401" ]
} || [ $wait_time -ge $MAX_WAIT ]; do
    echo "[...] Waiting for Elasticsearch to respond... ($wait_time/$MAX_WAIT seconds elapsed)"
    sleep 5
    wait_time=$((wait_time + 5))
done
if [ $wait_time -ge $MAX_WAIT ]; then
    echo "[ERR] Elasticsearch did not become available after $MAX_WAIT seconds. Check logs with: journalctl -xeu elasticsearch.service"
    exit 1
fi
echo "[OK] Elasticsearch is up and responding."

if [ "$FRESH_INSTALL" = "true" ] || [ "$RESET_ELASTIC_PASSWORD" = "true" ]; then
    echo "[CREDS] Resetting password for 'elastic' user..."
    ELASTIC_PASSWORD=$($SUDO /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b -s)
    if [[ $? -ne 0 ]]; then
        echo "[ERR] Failed to reset elastic user password."
        exit 1
    fi
    echo "[TEST] Verifying access with new password..."
    curl -k -u elastic:"$ELASTIC_PASSWORD" https://$NODE_IP:9200 || echo "Curl failed, check logs for details"
else
    ELASTIC_PASSWORD="(not rotated — use RESET_ELASTIC_PASSWORD=true to force reset)"
    echo "[CREDS] Skipping password reset (rerun detected)."
fi

# ---------------------------------------------------------------------------
# WUG role + user provisioning
# Creates the 'wug_tasks_cleanup' role (allow_restricted_indices on .tasks)
# and a dedicated WUG user with superuser + that role, so task cleanup works
# without needing the built-in elastic account.
# Skipped automatically when the elastic password is unknown (re-run without
# RESET_ELASTIC_PASSWORD=true) — re-run with that flag or set WUG_USER_PASSWORD
# and RESET_ELASTIC_PASSWORD=true to force the setup.
# ---------------------------------------------------------------------------
echo "[WUG] Provisioning WhatsUp Gold role and user..."
if [ -n "$ELASTIC_PASSWORD" ] && [ "${ELASTIC_PASSWORD:0:1}" != "(" ]; then
    if [ -z "$WUG_USER_PASSWORD" ]; then
        if command -v openssl &>/dev/null; then
            WUG_USER_PASSWORD="$(openssl rand -hex 16)"
        else
            WUG_USER_PASSWORD="$(dd if=/dev/urandom bs=48 count=1 2>/dev/null | base64 | tr -dc 'A-Za-z0-9' | cut -c1-24)"
        fi
        echo "[WUG] Auto-generated password for '$WUG_USER'."
    else
        echo "[WUG] Using caller-supplied WUG_USER_PASSWORD."
    fi

    echo "[WUG] Creating role 'wug_tasks_cleanup'..."
    ROLE_HTTP="$(curl -sk -o /dev/null -w "%{http_code}" \
        -u "elastic:${ELASTIC_PASSWORD}" \
        -X PUT "https://${NODE_IP}:9200/_security/role/wug_tasks_cleanup" \
        -H 'Content-Type: application/json' -d '{
          "indices": [{
            "names": [".tasks"],
            "privileges": ["read","delete"],
            "allow_restricted_indices": true
          }]
        }')"
    if [ "$ROLE_HTTP" = "200" ]; then
        echo "[OK] Role 'wug_tasks_cleanup' created/updated."
    else
        echo "[WARN] Role creation returned HTTP $ROLE_HTTP — check ES logs."
    fi

    echo "[WUG] Creating user '$WUG_USER' with roles [superuser, wug_tasks_cleanup]..."
    USER_HTTP="$(curl -sk -o /dev/null -w "%{http_code}" \
        -u "elastic:${ELASTIC_PASSWORD}" \
        -X PUT "https://${NODE_IP}:9200/_security/user/${WUG_USER}" \
        -H 'Content-Type: application/json' -d "{
          \"password\": \"${WUG_USER_PASSWORD}\",
          \"roles\": [\"superuser\", \"wug_tasks_cleanup\"]
        }")"
    if [ "$USER_HTTP" = "200" ]; then
        echo "[OK] User '$WUG_USER' created/updated."
    else
        echo "[WARN] User creation returned HTTP $USER_HTTP — check ES logs."
    fi
else
    echo "[SKIP] Elastic password not available (re-run detected). WUG user not configured."
    echo "--> Re-run with: RESET_ELASTIC_PASSWORD=true $0"
fi
# ---------------------------------------------------------------------------

echo "[DONE] DONE: Elasticsearch setup is complete and verified."
echo "----------------------------------------"
echo "Recap:"
echo "  Elasticsearch version: $ELASTIC_VERSION"
echo "  Node IP: $NODE_IP"
echo "  Hostname: $NODE_IP_HOSTNAME"
echo "  CA dir: $CERT_DIR/ca/ca"
echo "  Node cert: $NODE_CERT"
echo "  Node key: $NODE_KEY"
echo "  Config file: $ES_CONFIG"
if [ "$FRESH_INSTALL" = "true" ] || [ "$RESET_ELASTIC_PASSWORD" = "true" ]; then
    echo "  [WARN] elastic password: $ELASTIC_PASSWORD"
    echo "  [WARN] SAVE THIS NOW — it will not be shown again."
else
    echo "  elastic password: $ELASTIC_PASSWORD"
fi
if [ -n "$WUG_USER_PASSWORD" ] && [ "${ELASTIC_PASSWORD:0:1}" != "(" ]; then
    echo "  WUG ES user:      $WUG_USER"
    echo "  [WARN] WUG ES password: $WUG_USER_PASSWORD"
    echo "  [WARN] SAVE THIS NOW — update WhatsUp Gold ES settings to use this account."
else
    echo "  WUG ES user:      (not configured — re-run with RESET_ELASTIC_PASSWORD=true)"
fi
echo "  Log: $LOGFILE"
echo "========================================"