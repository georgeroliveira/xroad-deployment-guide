#!/bin/bash
# install-xroad-autologin.sh | georgeroliveira | MIT
# Ubuntu 24.04 (x86_64) | X-Road Auto Login | INTERACTIVE installation

set -euo pipefail
set -o errtrace
umask 027

# ===== Constants =====
declare -r XROAD_VERSION="7.8.0"
declare -r UBUNTU_VERSION_REQUIRED="24.04"
declare -r UBUNTU_CODENAME_REQUIRED="noble"
declare -r XROAD_SUITE="${UBUNTU_CODENAME_REQUIRED}-${XROAD_VERSION}"
declare -r XROAD_PACKAGE="xroad-autologin"

declare -r LOG_FILE="/var/log/xroad-autologin-install.log"

declare -r ARQUIVO_PIN="${ARQUIVO_PIN:-/etc/xroad/autologin}"
declare -r SERVICO="${SERVICO:-xroad-autologin.service}"

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

check_xroad_installed() {
  dpkg -l | grep -Eq "^ii\s+xroad-(centralserver|securityserver)\b" \
    || die "X-Road Central Server or Security Server not found. Install X-Road first."

  log OK "X-Road detected"
}

# ===== System preparation =====
prepare_system() {
  log INFO "Updating APT..."
  apt-get update -qq

  log INFO "Installing minimum dependencies..."
  apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    openssl

  log OK "System prepared"
}

# ===== PIN configuration =====
configurar_pin() {
  local pin=""
  local pin2=""

  read -s -r -p "Enter PIN for autologin: " pin
  echo
  [[ -n "$pin" ]] || die "Empty PIN. Aborting."

  read -s -r -p "Confirm PIN: " pin2
  echo
  [[ "$pin" == "$pin2" ]] || die "PIN does not match. Aborting."

  install -d -m 0755 "$(dirname "$ARQUIVO_PIN")"
  printf '%s' "$pin" > "$ARQUIVO_PIN"
  chown xroad:xroad "$ARQUIVO_PIN"
  chmod 600 "$ARQUIVO_PIN"

  pin=""
  pin2=""
  unset pin pin2

  log OK "PIN saved to ${ARQUIVO_PIN} with secure permissions"
}

# ===== Installation =====
instalar_xroad_autologin() {
  log INFO "Installing ${XROAD_PACKAGE}..."

  if ! apt-get install -y "$XROAD_PACKAGE"; then
    log ERRO "Failed to install ${XROAD_PACKAGE}. Attempting dpkg/apt recovery..."
    dpkg --configure -a || true
    apt-get -f install -y || true
    die "Installation of ${XROAD_PACKAGE} failed. Check log: ${LOG_FILE}"
  fi

  dpkg -s "$XROAD_PACKAGE" >/dev/null 2>&1 \
    || die "Package ${XROAD_PACKAGE} is not correctly installed"

  log OK "${XROAD_PACKAGE} installed"
}

# ===== Service =====
habilitar_servico() {
  local unit="$SERVICO"
  [[ "$unit" == *.service ]] || unit="${unit}.service"

  log INFO "Enabling and restarting service ${unit}..."
  systemctl enable --now "$unit" >/dev/null
  systemctl restart "$unit"

  systemctl is-active --quiet "$unit" \
    || { systemctl status "$unit" --no-pager || true; die "Service ${unit} is not active"; }

  log OK "Service ${unit} is active"
}

# ===== Post-check =====
pos_check() {
  log INFO "Running post-installation checks..."

  systemctl reset-failed 2>/dev/null || true

  if systemctl list-units "xroad-*" --state=failed --no-legend --no-pager \
      | grep -v 'not-found' | grep -q .; then
    systemctl list-units "xroad-*" --state=failed --no-pager || true
    die "There are X-Road services in FAILED state"
  fi

  log OK "Post-check complete"
}

main() {
  require_root
  require_tty
  check_xroad_installed

  log INFO "Starting: X-Road Auto Login ${XROAD_VERSION} (${XROAD_SUITE})"

  prepare_system
  instalar_xroad_autologin
  configurar_pin
  habilitar_servico
  pos_check

  log OK "Installation complete"
  log INFO "Log: ${LOG_FILE}"
}

main "$@"