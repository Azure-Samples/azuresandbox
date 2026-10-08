#!/bin/bash
# Blocks until cloud-init has finished and the dpkg/apt locks are free, so that VM extensions
# which install packages (e.g. AzureMonitorLinuxAgent) do not race cloud-init or first-boot
# apt-daily / unattended-upgrades for the package manager lock (see issue #798).
# Executed via azurerm_virtual_machine_run_command before the AMA extension is installed.
#
# While waiting, a progress line is logged every report_seconds so the run command's instance view
# (az vm run-command show --instance-view) shows how far provisioning has progressed: the current
# cloud-init stage, the most recent cloud-init module, the latest step logged by the user script,
# how many cloud-config packages are installed, how many .deb files have been downloaded, how many
# Az PowerShell submodules have been installed, and which
# processes hold the dpkg/apt locks.

set -uo pipefail

timeout_seconds=1200       # wait budget for the dpkg/apt locks after cloud-init (20 min)
cloud_init_timeout=3600    # wait budget for cloud-init to finish (60 min)
poll_seconds=10
report_seconds=30
required_idle_checks=3     # consecutive idle checks required before declaring the locks free

locks=(
  /var/lib/dpkg/lock-frontend
  /var/lib/dpkg/lock
  /var/lib/apt/lists/lock
  /var/cache/apt/archives/lock
)

packages=()

log() {
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"
}

apt_busy() {
  local lock
  for lock in "${locks[@]}"; do
    if [ -e "$lock" ] && fuser "$lock" >/dev/null 2>&1; then
      return 0
    fi
  done

  if systemctl is-active --quiet apt-daily.service || systemctl is-active --quiet apt-daily-upgrade.service; then
    return 0
  fi

  return 1
}

# Current cloud-init stage (1-4) and time spent in it, from /run/cloud-init/status.json.
stage_info() {
  python3 - <<'PY' 2>/dev/null || echo "stage=unknown"
import json, time
stages = ["init-local", "init", "modules-config", "modules-final"]
v1 = json.load(open("/run/cloud-init/status.json"))["v1"]
current = v1.get("stage")
if current in stages:
    started = (v1.get(current) or {}).get("start") or 0
    # Newer cloud-init records stage start times as seconds since boot rather than epoch time.
    now = time.time() if started > 1e9 else float(open("/proc/uptime").read().split()[0])
    print(f"stage={current}({stages.index(current) + 1}/4,{int(max(now - started, 0))}s)")
else:
    finished = [s for s in stages if (v1.get(s) or {}).get("finished")]
    print(f"stage=none({len(finished)}/4 finished)")
PY
}

# Per-stage durations, logged once cloud-init finishes to help baseline future progress estimates.
stage_durations() {
  python3 - <<'PY' 2>/dev/null || echo "unavailable"
import json
stages = ["init-local", "init", "modules-config", "modules-final"]
v1 = json.load(open("/run/cloud-init/status.json"))["v1"]
parts = []
for s in stages:
    st = v1.get(s) or {}
    if st.get("start") and st.get("finished"):
        parts.append(f"{s}={int(st['finished'] - st['start'])}s")
print(" ".join(parts) or "unavailable")
PY
}

# Most recent step logged by the module's cloud-init user script (configure-vm-jumpbox-linux.sh).
user_script_step() {
  local step
  step=$(grep -vE '^(=+)?$' /var/log/configure-vm-jumpbox-linux.log 2>/dev/null | tail -1 | tr -s ' ' | cut -c1-80)
  echo "step=\"${step:-none}\""
}

# Az submodules installed so far by Install-Module -Name Az -Scope AllUsers (one directory each).
az_module_progress() {
  local count
  count=$(find /usr/local/share/powershell/Modules -mindepth 1 -maxdepth 1 -type d -name 'Az.*' 2>/dev/null | wc -l)
  echo "az_modules=${count}"
}

current_module() {
  local module
  module=$(grep -oP 'Running module \K[a-z_]+' /var/log/cloud-init.log 2>/dev/null | tail -1)
  echo "${module:-none}"
}

# Packages listed in the cloud-config; read lazily because the file appears during the init stage.
load_packages() {
  [ "${#packages[@]}" -gt 0 ] && return
  mapfile -t packages < <(python3 -c '
import yaml
cfg = yaml.safe_load(open("/var/lib/cloud/instance/cloud-config.txt")) or {}
print("\n".join(p for p in cfg.get("packages", []) if isinstance(p, str)))
' 2>/dev/null)
}

package_progress() {
  local installed=0 pkg debs
  load_packages
  for pkg in "${packages[@]}"; do
    # shellcheck disable=SC2016 # ${Status} is a dpkg-query format field, not a shell expansion
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
      installed=$((installed + 1))
    fi
  done
  debs=$(find /var/cache/apt/archives -maxdepth 1 -name '*.deb' 2>/dev/null | wc -l)
  echo "packages=${installed}/${#packages[@]} debs_downloaded=${debs}"
}

lock_holders() {
  local pids
  pids=$(fuser "${locks[@]}" 2>/dev/null | tr -s ' \t' '\n' | grep -E '^[0-9]+$' | sort -u | paste -sd, -)
  if [ -z "$pids" ]; then
    echo "apt_lock=free"
  else
    echo "apt_lock=$(ps -o comm= -p "$pids" 2>/dev/null | sort -u | paste -sd, -)"
  fi
}

# cloud-init errors are surfaced by the module's unit tests; this script only enforces ordering.
log "Waiting for cloud-init to finish..."
start=$(date +%s)
last_report=0

while :; do
  status=$(cloud-init status 2>/dev/null | awk '/^status:/ {print $2}')
  case "$status" in
    done | error | degraded) break ;;
  esac

  now=$(date +%s)
  if [ $((now - start)) -ge "$cloud_init_timeout" ]; then
    log "Timed out after ${cloud_init_timeout}s waiting for cloud-init to finish"
    log "progress: elapsed=$((now - start))s $(stage_info) module=$(current_module) $(user_script_step) $(package_progress) $(az_module_progress) $(lock_holders)"
    exit 1
  fi

  if [ $((now - last_report)) -ge "$report_seconds" ]; then
    log "progress: elapsed=$((now - start))s status=${status:-unknown} $(stage_info) module=$(current_module) $(user_script_step) $(package_progress) $(az_module_progress) $(lock_holders)"
    last_report=$now
  fi

  sleep "$poll_seconds"
done

log "cloud-init finished after $(($(date +%s) - start))s: $(cloud-init status 2>/dev/null | tr '\n' ' ')"
log "cloud-init stage durations: $(stage_durations)"

log "Waiting for dpkg/apt locks to be released..."
start=$(date +%s)
last_report=0
idle_checks=0

while [ "$idle_checks" -lt "$required_idle_checks" ]; do
  if apt_busy; then
    idle_checks=0
  else
    idle_checks=$((idle_checks + 1))
  fi

  now=$(date +%s)
  if [ $((now - start)) -ge "$timeout_seconds" ]; then
    log "Timed out after ${timeout_seconds}s waiting for dpkg/apt locks to be released ($(lock_holders))"
    exit 1
  fi

  if [ "$idle_checks" -eq 0 ] && [ $((now - last_report)) -ge "$report_seconds" ]; then
    log "progress: elapsed=$((now - start))s $(lock_holders)"
    last_report=$now
  fi

  sleep "$poll_seconds"
done

log "dpkg/apt locks are free"
exit 0
