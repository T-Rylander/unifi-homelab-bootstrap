#!/usr/bin/env bash
# UniFi Device Adoption Helper
# PURPOSE: Assist with Layer 3 adoption issues by issuing set-inform via SSH.
# WHY: Devices sometimes fail to discover controller automatically (DNS/Layer2). This script standardizes recovery.
set -euo pipefail
IFS=$'\n\t'

LOG_FILE="adopt.log"
exec > >(tee -a "$LOG_FILE") 2>&1

function usage(){
  cat <<EOF
Usage:
  sudo bash adopt-devices.sh -c <controller_ip> [-d <device_ip>] [-f devices.txt] [-u <ssh_user>] [-k <ssh_key>] [-p]

Options:
  -c    Controller IP or FQDN (required) e.g. 192.168.1.10
  -d    Single device IP to adopt
  -f    File containing list of device IPs (one per line) - ignored if -d used
  -u    SSH username (default: ubnt)
  -k    Path to SSH private key (optional, overrides password auth)
  -p    Prompt for SSH password (not recommended; use key)
  -h    Help

Examples:
  sudo bash adopt-devices.sh -c 192.168.1.10 -d 192.168.1.22
  sudo bash adopt-devices.sh -c unifi.rylan-home.local -f devices.txt -u ubnt -k /root/.ssh/unifi
EOF
}

function info(){ echo "[INFO] $*"; }
function warn(){ echo "[WARN] $*"; }
function fatal(){ echo "[ERROR] $*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
  fatal "Run as root to avoid key permission issues."
fi

CONTROLLER=""; DEVICE=""; LIST_FILE=""; SSH_USER="ubnt"; SSH_KEY=""; PROMPT_PASS=0
while getopts ":c:d:f:u:k:ph" opt; do
  case $opt in
    c) CONTROLLER="$OPTARG";;
    d) DEVICE="$OPTARG";;
    f) LIST_FILE="$OPTARG";;
    u) SSH_USER="$OPTARG";;
    k) SSH_KEY="$OPTARG";;
    p) PROMPT_PASS=1;;
    h) usage; exit 0;;
    :) fatal "Missing value for -$OPTARG";;
    \?) fatal "Invalid option -$OPTARG";;
  esac
done
shift $((OPTIND-1))

[[ -z "$CONTROLLER" ]] && fatal "Controller (-c) is required."

if [[ -n "$DEVICE" && -n "$LIST_FILE" ]]; then
  warn "Both -d and -f provided; using -d (single device)."
  LIST_FILE=""
fi

if [[ -z "$DEVICE" && -z "$LIST_FILE" ]]; then
  fatal "Specify either -d <device_ip> or -f <file>."
fi

SSH_PASS=""
if [[ $PROMPT_PASS -eq 1 ]]; then
  read -r -s -p "SSH Password: " SSH_PASS; echo ""
fi

if [[ -n "$SSH_KEY" && ! -f "$SSH_KEY" ]]; then
  fatal "SSH key not found: $SSH_KEY"
fi

function adopt(){
  local ip="$1"
  info "Adopting device $ip -> controller $CONTROLLER"
  local auth_opts=()
  if [[ -n "$SSH_KEY" ]]; then
    auth_opts=(-i "$SSH_KEY")
  fi
  if [[ -n "$SSH_PASS" ]]; then
    # Using sshpass only if installed; avoidance of storing password
    if ! command -v sshpass >/dev/null 2>&1; then
      fatal "sshpass required for password mode; install or use key (-k)."
    fi
    auth_opts=(sshpass -p "$SSH_PASS" ssh)
  fi
  # shellcheck disable=SC2029
  if [[ -n "$SSH_PASS" ]]; then
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$ip" "set-inform http://$CONTROLLER:8080/inform" || warn "Adoption command failed for $ip"
  else
    ssh -o StrictHostKeyChecking=no "${auth_opts[@]}" "$SSH_USER@$ip" "set-inform http://$CONTROLLER:8080/inform" || warn "Adoption command failed for $ip"
  fi
}

if [[ -n "$DEVICE" ]]; then
  adopt "$DEVICE"
else
  if [[ ! -f "$LIST_FILE" ]]; then
    fatal "Device list file not found: $LIST_FILE"
  fi
  mapfile -t devices < <(grep -Ev '^\s*#|^\s*$' "$LIST_FILE")
  for d in "${devices[@]}"; do
    adopt "$d"
  done
fi

info "Adoption attempts complete. Check UniFi UI for status (may show 'Pending' before 'Adopted')."
