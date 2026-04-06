#!/bin/bash
# xroad-remove.sh | georgeroliveira | MIT
# Ubuntu 24.04 (x86_64) | X-Road | FULL removal (dedicated VM)
# MODE: interactive by default | use --yes for non-interactive

set -euo pipefail
set -o errtrace
umask 027

# ===== Constants =====
declare -r LOG_FILE="/var/log/xroad-remove.log"

declare -r POSTGRES_USER="postgres"
declare -ra XROAD_DBS=(centerui_production messagelog serverconf op-monitor)
declare -ra XROAD_DB_USERS=(centerui centerui_admin serverconf serverconf_admin messagelog messagelog_admin opmonitor opmonitor_admin)

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

# ===== Mode (interactive by default) =====
INTERACTIVE=true
for arg in "$@"; do
  [[ "$arg" == "--yes" ]] && INTERACTIVE=false
done

confirm() {
  local msg="$1"
  if [[ "$INTERACTIVE" == true ]]; then
    read -r -p "$msg (y/N): " ans
    ans="${ans,,}"
    [[ "$ans" =~ ^(s|sim|y|yes)$ ]] || {
      log INFO "Cancelled by user."
      exit 0
    }
  fi
}

# ===== Pre-checks =====
require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Run as root: sudo $0"
}

require_tty() {
  [[ -t 0 ]] || die "No TTY (interactive terminal). Run in a terminal."
}

# ===== Stop services =====
parar_servicos() {
  log INFO "Stopping services..."

  local services=(xroad-signer xroad-confclient xroad-proxy xroad-monitor xroad-centralserver xroad-securityserver nginx postgresql)

  for svc in "${services[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      log INFO "Stopping: $svc"
      systemctl stop "$svc" 2>/dev/null || log WARN "Failed to stop $svc"
    fi
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
      systemctl disable "$svc" 2>/dev/null || true
    fi
  done

  log OK "Services processed"
}

# ===== PostgreSQL =====
remover_bancos_postgres() {
  if ! id -u "$POSTGRES_USER" >/dev/null 2>&1; then
    log WARN "User '${POSTGRES_USER}' does not exist. Skipping database removal."
    return 0
  fi

  log INFO "Removing X-Road databases and users (PostgreSQL)..."

  for db in "${XROAD_DBS[@]}"; do
    log INFO "Dropping database: $db"
    runuser -u "$POSTGRES_USER" -- dropdb "$db" 2>/dev/null || true
  done

  for u in "${XROAD_DB_USERS[@]}"; do
    log INFO "Dropping user: $u"
    runuser -u "$POSTGRES_USER" -- psql -v ON_ERROR_STOP=1 -c "DROP USER IF EXISTS ${u};" 2>/dev/null || true
  done

  log OK "PostgreSQL processed"
}

# ===== Package removal =====
remover_pacotes() {
  log INFO "Removing X-Road, nginx and PostgreSQL packages..."

  local xroad_pkgs=() nginx_pkgs=() pg_pkgs=()

  mapfile -t xroad_pkgs < <(dpkg-query -W -f='${binary:Package}\n' 'xroad-*' 2>/dev/null || true)
  mapfile -t nginx_pkgs < <(dpkg-query -W -f='${binary:Package}\n' 'nginx*' 2>/dev/null || true)
  mapfile -t pg_pkgs    < <(dpkg-query -W -f='${binary:Package}\n' 'postgresql*' 2>/dev/null || true)

  ((${#xroad_pkgs[@]})) && apt-get purge -y "${xroad_pkgs[@]}" || true
  ((${#nginx_pkgs[@]})) && apt-get purge -y "${nginx_pkgs[@]}" || true
  ((${#pg_pkgs[@]}))    && apt-get purge -y "${pg_pkgs[@]}" || true

  apt-get autoremove -y || true
  apt-get autoclean -y || true

  log OK "Packages processed"
}

# ===== File removal =====
remover_arquivos() {
  log INFO "Removing directories and configuration files..."

  local paths=(
    "/etc/xroad"
    "/usr/share/xroad"
    "/var/lib/xroad"
    "/var/log/xroad"
    "/etc/xroad.properties"
    "/var/tmp/xroad"
  )

  for p in "${paths[@]}"; do
    [[ -e "$p" ]] && rm -rf "$p" 2>/dev/null || true
  done

  log OK "Files processed"
}

# ===== Main =====
main() {
  require_root
  require_tty

  log WARN "WARNING: This will perform a FULL removal of X-Road."
  confirm "Do you want to continue?"

  confirm "Stop ALL services?"
  parar_servicos

  confirm "Remove PostgreSQL databases and users?"
  remover_bancos_postgres

  confirm "Remove ALL packages?"
  remover_pacotes

  confirm "Remove directories and configuration files?"
  remover_arquivos

  log OK "Removal complete"
  log INFO "Log: ${LOG_FILE}"
}

main "$@"