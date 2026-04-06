#!/bin/bash
# install-xroad-centralserver.sh | georgeroliveira | MIT
# Ubuntu 24.04 (x86_64) | X-Road Central Server | INTERACTIVE installation

set -euo pipefail
set -o errtrace
umask 027

# ===== Constants =====
declare -r XROAD_VERSION="7.8.0"
declare -r UBUNTU_VERSION_REQUIRED="24.04"
declare -r UBUNTU_CODENAME_REQUIRED="noble"
declare -r XROAD_SUITE="${UBUNTU_CODENAME_REQUIRED}-${XROAD_VERSION}"
declare -r XROAD_PACKAGE="xroad-centralserver"

declare -r LOCALE_VALUE="en_US.UTF-8"

declare -r XROAD_KEYRING="/usr/share/keyrings/niis-artifactory-keyring.gpg"
declare -r XROAD_LIST="/etc/apt/sources.list.d/xroad.list"
declare -r XROAD_REPO_URL="https://artifactory.niis.org/xroad-release-deb"
declare -r XROAD_GPG_URL="https://x-road.eu/gpg/key/public/niis-artifactory-public.gpg"

declare -r LOG_FILE="/var/log/xroad-centralserver-install.log"

declare -r MIN_RAM_MB=2048
declare -r MIN_DISK_MB=5120
declare -r PG_REQUIRED_PORT=5432

# ===== Logging + Errors =====
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
  local tipo="$1"; shift
  local msg="$*"
  local cor=""

  case "$tipo" in
    INFO) cor="\033[1;34m" ;;
    OK)   cor="\033[1;32m" ;;
    WARN) cor="\033[1;33m" ;;
    ERRO) cor="\033[1;31m" ;;
    *)    cor="" ;;
  esac

  echo -e "${cor}[$tipo]\033[0m $msg"
}

die() {
  log ERRO "$*"
  exit 1
}

on_err() {
  log ERRO "Failure at line ${1}: ${2}"
  log ERRO "Log: ${LOG_FILE}"
  exit 1
}

trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR

# ===== Pre-checks =====
require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Run as root: sudo $0"
}

require_tty() {
  [[ -t 0 ]] || die "No TTY (interactive terminal). Run in a terminal."
}

validar_ubuntu() {
  source /etc/os-release 2>/dev/null || die "Could not identify the operating system"

  [[ "${ID:-}" == "ubuntu" ]] || die "Unsupported system: ${ID:-unknown}"
  [[ "${VERSION_ID:-}" == "$UBUNTU_VERSION_REQUIRED" ]] \
    || die "Ubuntu ${UBUNTU_VERSION_REQUIRED} required. Detected: ${VERSION_ID:-unknown}"
  [[ "${VERSION_CODENAME:-}" == "$UBUNTU_CODENAME_REQUIRED" ]] \
    || die "Expected codename: ${UBUNTU_CODENAME_REQUIRED}. Detected: ${VERSION_CODENAME:-unknown}"

  log OK "Ubuntu ${VERSION_ID} (${VERSION_CODENAME}) OK"
}

check_disk_ram() {
  local ram_mb var_free_kb var_free_mb

  ram_mb="$(free -m | awk '/^Mem:/ {print $2}')"
  var_free_kb="$(df -Pk /var | awk 'NR==2 {print $4}')"

  [[ "$ram_mb" =~ ^[0-9]+$ ]] || die "Failed to validate RAM"
  [[ "$var_free_kb" =~ ^[0-9]+$ ]] || die "Failed to validate disk space in /var"

  var_free_mb=$((var_free_kb / 1024))

  [[ "$ram_mb" -ge "$MIN_RAM_MB" ]] \
    || die "Insufficient RAM: ${ram_mb}MB (minimum: ${MIN_RAM_MB}MB)"
  [[ "$var_free_mb" -ge "$MIN_DISK_MB" ]] \
    || die "Insufficient disk space in /var: ${var_free_mb}MB (minimum: ${MIN_DISK_MB}MB)"

  log OK "RAM: ${ram_mb}MB | /var free: ${var_free_mb}MB"
}

check_connectivity() {
  log INFO "Validating connectivity..."

  getent hosts artifactory.niis.org >/dev/null || die "DNS failure (artifactory.niis.org)"

  curl -fsSLI --max-time 10 "${XROAD_REPO_URL}/" >/dev/null \
    || die "No access to repository: ${XROAD_REPO_URL}"

  curl -fsSLI --max-time 10 "${XROAD_GPG_URL}" >/dev/null \
    || die "No access to GPG key"

  log OK "Connectivity OK"
}

# ===== Port 5432 check =====
check_porta_5432() {
  log INFO "Checking port ${PG_REQUIRED_PORT}..."

  if ss -lntp 2>/dev/null | grep -q ":${PG_REQUIRED_PORT} .*docker-proxy"; then
    log WARN "Docker is occupying port ${PG_REQUIRED_PORT}. Stopping Docker..."
    systemctl stop docker || die "Failed to stop Docker"
    log OK "Docker stopped. Port ${PG_REQUIRED_PORT} released."
    log WARN "Restart Docker manually after installation is complete."
    return 0
  fi

  ss -lntp 2>/dev/null | grep -q ":${PG_REQUIRED_PORT} " \
    && die "Port ${PG_REQUIRED_PORT} occupied by unmanaged process. Free it and try again."

  log OK "Port ${PG_REQUIRED_PORT} available"
}

# ===== System preparation =====
prepare_system() {
  log INFO "Updating APT index..."
  apt-get update -qq

  log INFO "Installing minimum dependencies..."
  apt-get install -y \
    ca-certificates \
    chrony \
    curl \
    dialog \
    gnupg \
    language-pack-en \
    locales \
    openjdk-21-jre-headless \
    openssl

  if [[ -n "${TZ_NAME:-}" ]]; then
    log INFO "Configuring timezone: ${TZ_NAME}"
    timedatectl set-timezone "$TZ_NAME" \
      || log WARN "Could not set timezone to ${TZ_NAME}"
  fi

  log INFO "Configuring locale ${LOCALE_VALUE}"

  locale-gen "$LOCALE_VALUE" >/dev/null 2>&1 \
    || log WARN "Failed to generate locale ${LOCALE_VALUE}"

  update-locale LANG="$LOCALE_VALUE" LC_ALL="$LOCALE_VALUE" >/dev/null 2>&1 \
    || log WARN "Failed to apply persistent locale"

  export LANG="$LOCALE_VALUE"
  export LC_ALL="$LOCALE_VALUE"

  log INFO "Enabling NTP (chrony)"
  systemctl enable --now chrony >/dev/null
  systemctl is-active --quiet chrony || die "chrony is not active"

  log OK "System prepared"
}

# ===== Official repository =====
adicionar_repo_xroad() {
  local candidate

  log INFO "Configuring X-Road key and repository (${XROAD_SUITE})..."

  install -d -m 0755 "$(dirname "$XROAD_KEYRING")"

  curl -fsSL "$XROAD_GPG_URL" -o "$XROAD_KEYRING" \
    || die "Failed to download GPG key: ${XROAD_GPG_URL}"

  [[ -s "$XROAD_KEYRING" ]] || die "Invalid or empty GPG key: ${XROAD_KEYRING}"
  chmod 0644 "$XROAD_KEYRING"

  cat > "$XROAD_LIST" <<EOF
deb [signed-by=${XROAD_KEYRING}] ${XROAD_REPO_URL} ${XROAD_SUITE} main
EOF

  apt-get update -qq || die "Failed to update APT index with X-Road repository"

  candidate="$(apt-cache policy "$XROAD_PACKAGE" | awk -F': ' '/Candidate:/ {print $2}')"
  [[ -n "$candidate" && "$candidate" != "(none)" ]] \
    || die "Package ${XROAD_PACKAGE} not available in configured repository"

  log OK "X-Road repository configured: ${XROAD_SUITE}"
}

# ===== Admin user (INTERACTIVE) =====
validar_senha() {
  local senha="${1:-}"

  [[ -n "$senha" ]] || return 1
  [[ ${#senha} -ge 8 ]] || return 1
  [[ "$senha" =~ [0-9] ]] || return 1
  [[ "$senha" =~ [[:alpha:]] ]] || return 1

  return 0
}

solicitar_senha_segura() {
  local usuario="${1:?user not provided}"
  local senha=""
  local senha_conf=""
  local tent=0

  log INFO "Password: minimum 8 characters, at least 1 letter and 1 number."

  while true; do
    ((++tent))
    [[ "$tent" -le 5 ]] || die "Too many invalid attempts to set password"

    read -s -r -p "Password for '$usuario': " senha
    echo
    read -s -r -p "Confirm password: " senha_conf
    echo

    if [[ -z "$senha" || -z "$senha_conf" ]]; then
      log ERRO "Password cannot be empty."
      continue
    fi

    if [[ "$senha" != "$senha_conf" ]]; then
      log ERRO "Passwords do not match."
      senha=""
      senha_conf=""
      continue
    fi

    if ! validar_senha "$senha"; then
      log ERRO "Password does not meet minimum policy."
      senha=""
      senha_conf=""
      continue
    fi

    chpasswd <<< "${usuario}:${senha}" || die "Failed to set password for '$usuario'"

    senha=""
    senha_conf=""
    unset senha senha_conf

    log OK "Password set for '$usuario'"
    return 0
  done
}

criar_usuario_admin() {
  local admin=""
  local resp=""
  local tent=0

  while true; do
    ((++tent))
    [[ "$tent" -le 5 ]] || die "Too many invalid attempts for username"

    read -r -p "Administrator username (do not use root/admin/xroad): " admin

    if [[ "$admin" =~ ^[a-z_][a-z0-9_-]*$ ]] &&
       [[ "$admin" != "root" ]] &&
       [[ "$admin" != "admin" ]] &&
       [[ "$admin" != "xroad" ]] &&
       [[ ${#admin} -ge 3 && ${#admin} -le 32 ]]; then
      break
    fi

    log ERRO "Invalid or reserved name. Try again."
  done

  if id "$admin" >/dev/null 2>&1; then
    log OK "User '$admin' already exists."
    read -r -p "Set new password? (y/N): " resp
    resp="${resp,,}"

    if [[ "$resp" =~ ^(s|sim|y|yes)$ ]]; then
      solicitar_senha_segura "$admin"
    else
      log INFO "Keeping current password."
    fi
  else
    log INFO "Creating user '$admin'..."
    adduser --gecos "" --disabled-password "$admin" \
      || die "Failed to create user '$admin'"

    solicitar_senha_segura "$admin"
  fi

  ADMIN_USER="$admin"
  log INFO "Use this user in the X-Road installer interactive screens: $admin"
}

# ===== Installation (INTERACTIVE) =====
instalar_xroad() {
  log INFO "Installing ${XROAD_PACKAGE} (interactive mode)..."
  log WARN "The installer will open debconf screens. Answer carefully."

  if ! DEBIAN_FRONTEND=dialog apt-get install -y "$XROAD_PACKAGE"; then
    log WARN "Installation of ${XROAD_PACKAGE} failed. Ensuring PostgreSQL is ready and retrying..."

    systemctl enable --now postgresql >/dev/null 2>&1 || true

    local i=0
    until pg_isready -q || [[ $i -ge 15 ]]; do
      sleep 2
      ((++i))
    done

    pg_isready -q || die "PostgreSQL did not respond. Check log: ${LOG_FILE}"

    dpkg --configure -a || true
    apt-get -f install -y || true
  fi

  dpkg -s "$XROAD_PACKAGE" >/dev/null 2>&1 \
    || die "Package ${XROAD_PACKAGE} is not correctly installed"

  log OK "${XROAD_PACKAGE} installed"
}

# ===== Post-check =====
pos_check() {
  log INFO "Running post-installation checks..."

  # Clear orphaned states from previous installations before checking failures
  systemctl reset-failed 2>/dev/null || true

  if systemctl list-units "xroad-*" --state=failed --no-legend --no-pager \
      | grep -v 'not-found' | grep -q .; then
    systemctl list-units "xroad-*" --state=failed --no-pager || true
    die "There are X-Road services in FAILED state"
  fi

  systemctl is-active --quiet postgresql \
    || die "PostgreSQL is not active"

  if ! systemctl list-units "xroad-*" --no-legend --no-pager | grep -q .; then
    die "No X-Road services found after installation"
  fi

  if command -v pg_isready >/dev/null 2>&1; then
    pg_isready -q \
      && log OK "PostgreSQL responding to pg_isready" \
      || log WARN "pg_isready not responding (PostgreSQL may still be starting)"
  fi

  if command -v psql >/dev/null 2>&1; then
    if runuser -u postgres -- psql -v ON_ERROR_STOP=1 -qtAc "SELECT 1" >/dev/null 2>&1; then
      log OK "PostgreSQL: connection OK (SELECT 1)"
    else
      log WARN "PostgreSQL: SELECT 1 test failed"
    fi
  else
    log WARN "psql not found for connection test"
  fi

  if ss -lntp 2>/dev/null | grep -q ':4000 '; then
    log OK "Port 4000 is LISTENING"
  else
    log WARN "Port 4000 not yet in LISTEN state"
  fi

  log OK "Post-check complete"
}

mostrar_status() {
  log INFO "X-Road services summary:"
  systemctl list-units "xroad-*" --no-pager --no-legend || true
}

main() {
  require_root
  require_tty
  validar_ubuntu
  check_disk_ram
  check_connectivity
  check_porta_5432

  log INFO "Starting installation: X-Road Central Server ${XROAD_VERSION} (${XROAD_SUITE})"

  prepare_system
  adicionar_repo_xroad
  criar_usuario_admin
  instalar_xroad
  pos_check
  mostrar_status

  log OK "Installation complete"
  log INFO "Access the Central Server at: https://$(hostname -f 2>/dev/null || hostname):4000/"
  log INFO "Log: ${LOG_FILE}"
}

main "$@"