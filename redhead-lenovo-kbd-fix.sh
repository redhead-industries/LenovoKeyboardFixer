#!/usr/bin/env bash
#===============================================================================
# Lenovo Keyboard Fixer
#===============================================================================
#  Project:    LenovoKeyboardFixer
#  Repository: https://github.com/redhead-industries/LenovoKeyboardFixer
#  License:    GNU General Public License v3.0
#  Author:     RedHead Industries - Technologies Branch (Founder: Matthew DaLuz)
#  Description:
#    A universal bugfix utility for Lenovo laptops running Linux where the
#    built-in keyboard becomes unresponsive after suspend or hibernate.
#
#    This script installs a post-resume hook compatible with systemd, elogind,
#    and pm-utils to reinitialize input devices automatically after resume.
#
#    Developed by RedHead Industries as part of our commitment to maintaining
#    Free and Open Source Software (FOSS) that enhances reliability, privacy,
#    and freedom for Linux users worldwide.
#
#===============================================================================
#  Supported Power Managers:
#    - systemd system-sleep
#    - elogind system-sleep
#    - pm-utils sleep.d
#
#  Usage:
#    sudo ./redhead-lenovo-kbd-fix.sh [install|uninstall|test|enable-kernel-quirk|disable-kernel-quirk|status]
#
#  Example:
#    sudo ./redhead-lenovo-kbd-fix.sh install
#
#===============================================================================
#  Disclaimer:
#    This software is provided "AS IS", without warranty of any kind.
#    Use at your own discretion. RedHead Industries is not responsible for
#    damage or system instability resulting from improper usage.
#===============================================================================

set -euo pipefail

# ----- Application constants -----
APP_NAME="redhead-lenovo-kbd-fix"
TAG="[${APP_NAME}]"
HOOK_NAME="99-${APP_NAME}"
HOOK_CONTENT_FILE="/usr/lib/${APP_NAME}/${APP_NAME}-hook.sh"
CONF_DIR="/etc/${APP_NAME}"
CONF_FILE="${CONF_DIR}/${APP_NAME}.conf"
GRUB_FILE="/etc/default/grub"
GRUB_D_SNIPPET="/etc/default/grub.d/50-${APP_NAME}.cfg"

# Preferred install directories (first existing path is used)
SYSD_SLEEP_DIRS=("/usr/lib/systemd/system-sleep" "/lib/systemd/system-sleep")
ELO_SLEEP_DIRS=("/usr/lib/elogind/system-sleep" "/lib/elogind/system-sleep")
PM_SLEEP_DIRS=("/etc/pm/sleep.d" "/usr/lib/pm-utils/sleep.d")

# ----- Logging and helper functions -----
log() { echo "${TAG} $*" >&2; logger -t "${APP_NAME}" -- "$*"; }
is_root() { [ "${EUID:-$(id -u)}" -eq 0 ]; }
die() { log "ERROR: $*"; exit 1; }

is_lenovo() {
  local v="/sys/class/dmi/id/sys_vendor"
  [ -r "$v" ] && grep -qi 'lenovo' "$v"
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

pick_dir() {
  # Pick the first existing directory from args, else create the first one
  for d in "$@"; do
    if [ -d "$d" ]; then echo "$d"; return 0; fi
  done
  echo "$1"
}

udev_settle() { has_cmd udevadm && udevadm settle --timeout=5 || true; }

ensure_paths() { mkdir -p "/usr/lib/${APP_NAME}" "$CONF_DIR"; }

#===============================================================================
#  POST-RESUME HOOK
#===============================================================================
# This is the core logic that revives the i8042/PS2 and I2C keyboard/touchpad
# interfaces after system resume. It will be automatically installed as a
# systemd, elogind, or pm-utils sleep hook.
#===============================================================================

write_hook_content() {
  cat > "${HOOK_CONTENT_FILE}" <<'EOF'
#!/usr/bin/env bash
# RedHead Lenovo Keyboard Fixer - Post-resume hook
set -uo pipefail
APP="redhead-lenovo-kbd-fix"
TAG="[${APP}]"
log(){ logger -t "${APP}" -- "$*"; echo "${TAG} $*" >&2; }
is_lenovo(){ [ -r /sys/class/dmi/id/sys_vendor ] && grep -qi 'lenovo' /sys/class/dmi/id/sys_vendor; }

# Rebind PS/2 keyboard + touchpad devices (serio stack)
rebind_serio() {
  local changed=0
  for drvctl in /sys/bus/serio/devices/serio*/drvctl; do
    [ -e "$drvctl" ] || continue
    echo reconnect > "$drvctl" 2>/dev/null && changed=1 || true
  done
  for drv in atkbd psmouse; do
    local base="/sys/bus/serio/drivers/${drv}"
    [ -d "$base" ] || continue
    for dev in "${base}"/serio*; do
      [ -e "$dev" ] || continue
      local id; id="$(basename "$dev")"
      echo "$id" > "${base}/unbind" 2>/dev/null || true
      echo "$id" > "${base}/bind" 2>/dev/null || true
      changed=1
    done
  done
  [ "$changed" -eq 1 ] && log "PS/2 (i8042/atkbd/psmouse) reinitialized"
}

# Rebind I2C HID devices (safety net for rare Lenovo models)
rebind_i2c_hid() {
  local base="/sys/bus/i2c/drivers/i2c_hid_acpi"
  [ -d "$base" ] || return 0
  for d in "${base}"/*:*; do
    [ -e "$d" ] || continue
    local name; name="$(basename "$d")"
    echo "$name" > "${base}/unbind" 2>/dev/null || true
    echo "$name" > "${base}/bind" 2>/dev/null || true
  done
  log "I2C HID devices rebound"
}

# Retrigger input subsystem for userspace recognition
retrigger_input() {
  command -v udevadm >/dev/null 2>&1 && udevadm trigger --subsystem-match=input --action=change 2>/dev/null || true
}

# Run only after resume and only on Lenovo hardware
case "${1:-}" in
  pre)  exit 0 ;;
  post|resume|thaw)
    is_lenovo || exit 0
    sleep 0.5
    command -v udevadm >/dev/null 2>&1 && udevadm settle --timeout=5 || true
    rebind_serio
    rebind_i2c_hid
    retrigger_input
    log "Keyboard fix applied successfully"
    ;;
esac
exit 0
EOF
  chmod 0755 "${HOOK_CONTENT_FILE}"
}

#===============================================================================
#  INSTALLATION FUNCTIONS
#===============================================================================

install_systemd_hook() {
  local dir="$(pick_dir "${SYSD_SLEEP_DIRS[@]}")"
  mkdir -p "$dir"
  cat > "${dir}/${HOOK_NAME}" <<EOF
#!/usr/bin/env bash
exec "${HOOK_CONTENT_FILE}" "\$1" "\$2"
EOF
  chmod 0755 "${dir}/${HOOK_NAME}"
  log "Installed systemd hook at ${dir}/${HOOK_NAME}"
}

install_elogind_hook() {
  local dir="$(pick_dir "${ELO_SLEEP_DIRS[@]}")"
  mkdir -p "$dir"
  cat > "${dir}/${HOOK_NAME}" <<EOF
#!/usr/bin/env bash
exec "${HOOK_CONTENT_FILE}" "\$1" "\$2"
EOF
  chmod 0755 "${dir}/${HOOK_NAME}"
  log "Installed elogind hook at ${dir}/${HOOK_NAME}"
}

install_pmutils_hook() {
  local dir="$(pick_dir "${PM_SLEEP_DIRS[@]}")"
  mkdir -p "$dir"
  cat > "${dir}/${HOOK_NAME}" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  thaw|resume) exec "'"${HOOK_CONTENT_FILE}"'" resume ;;
  *) exit 0 ;;
esac
EOF
  sed -i "s#\"'\"${HOOK_CONTENT_FILE}\"'\"#\"${HOOK_CONTENT_FILE}\"#g" "${dir}/${HOOK_NAME}"
  chmod 0755 "${dir}/${HOOK_NAME}"
  log "Installed pm-utils hook at ${dir}/${HOOK_NAME}"
}

remove_hooks() {
  for d in "${SYSD_SLEEP_DIRS[@]}" "${ELO_SLEEP_DIRS[@]}" "${PM_SLEEP_DIRS[@]}"; do
    [ -f "${d}/${HOOK_NAME}" ] && rm -f "${d}/${HOOK_NAME}" && log "Removed ${d}/${HOOK_NAME}" || true
  done
  rm -f "${HOOK_CONTENT_FILE}" && log "Removed ${HOOK_CONTENT_FILE}" || true
  rmdir --ignore-fail-on-non-empty "/usr/lib/${APP_NAME}" 2>/dev/null || true
}

#===============================================================================
#  KERNEL QUIRKS (Optional)
#===============================================================================
# Enables i8042 parameters in GRUB for deeper compatibility with legacy PS/2
# controllers on some Lenovo models.
#===============================================================================

enable_kernel_quirk() {
  mkdir -p "$(dirname "$GRUB_D_SNIPPET")"
  cat > "${GRUB_D_SNIPPET}" <<'EOF'
# Added by Lenovo Keyboard Fixer (i8042 quirks)
GRUB_CMDLINE_LINUX="${GRUB_CMDLINE_LINUX} i8042.reset i8042.nomux"
EOF
  log "Enabled kernel quirk snippet at ${GRUB_D_SNIPPET}"
  if has_cmd update-grub; then
    update-grub
  elif has_cmd grub-mkconfig; then
    local cfg="/boot/grub/grub.cfg"
    [ -d /boot/grub2 ] && cfg="/boot/grub2/grub.cfg"
    grub-mkconfig -o "$cfg"
  else
    log "Manual GRUB update required."
  fi
}

disable_kernel_quirk() {
  [ -f "${GRUB_D_SNIPPET}" ] && rm -f "${GRUB_D_SNIPPET}" && log "Removed ${GRUB_D_SNIPPET}" || true
  if has_cmd update-grub; then
    update-grub
  elif has_cmd grub-mkconfig; then
    local cfg="/boot/grub/grub.cfg"
    [ -d /boot/grub2 ] && cfg="/boot/grub2/grub.cfg"
    grub-mkconfig -o "$cfg"
  fi
}

#===============================================================================
#  COMMANDS
#===============================================================================

cmd_install() {
  is_root || die "Run as root."
  is_lenovo || die "This fix only applies on Lenovo hardware."
  ensure_paths
  write_hook_content
  local installed=0
  if [ -d /run/systemd/system ] || pidof systemd >/dev/null 2>&1; then
    install_systemd_hook; installed=1
  fi
  if [ "$installed" -eq 0 ] && [ -d "${ELO_SLEEP_DIRS[0]}" -o -d "${ELO_SLEEP_DIRS[1]}" ]; then
    install_elogind_hook; installed=1
  fi
  if [ "$installed" -eq 0 ] && ( [ -d "${PM_SLEEP_DIRS[0]}" ] || [ -d "${PM_SLEEP_DIRS[1]}" ] ); then
    install_pmutils_hook; installed=1
  fi
  [ "$installed" -eq 1 ] || die "No compatible power management system detected."
  log "Installation complete. Keyboard fix will now auto-run on resume."
  log "Tip: run '$0 enable-kernel-quirk' to enable kernel parameters for older controllers."
}

cmd_uninstall() {
  is_root || die "Run as root."
  remove_hooks
  log "Uninstalled successfully. Kernel quirk snippet remains unless manually disabled."
}

cmd_test() {
  is_root || die "Run as root."
  is_lenovo || die "This fix only applies on Lenovo hardware."
  log "Applying fix immediately..."
  bash "${HOOK_CONTENT_FILE}" post suspend || die "Hook missing. Run 'install' first."
  log "If your keyboard was previously unresponsive, it should now work."
}

cmd_status() {
  echo "---- ${APP_NAME} STATUS ----"
  if is_lenovo; then echo "Hardware: Lenovo ✔"; else echo "Hardware: Not Lenovo"; fi
  for d in "${SYSD_SLEEP_DIRS[@]}" "${ELO_SLEEP_DIRS[@]}" "${PM_SLEEP_DIRS[@]}"; do
    [ -f "${d}/${HOOK_NAME}" ] && echo "Hook found: ${d}/${HOOK_NAME}"
  done
  [ -f "${HOOK_CONTENT_FILE}" ] && echo "Core hook exists: ${HOOK_CONTENT_FILE}"
  if grep -qs "i8042.reset" "${GRUB_FILE}" || [ -f "${GRUB_D_SNIPPET}" ]; then
    echo "Kernel quirk: enabled (check /proc/cmdline)"
  else
    echo "Kernel quirk: not enabled"
  fi
  echo "Logs: 'journalctl -b | grep ${APP_NAME}' for recent activity."
}

#===============================================================================
#  MAIN
#===============================================================================

case "${1:-}" in
  install)            cmd_install ;;
  uninstall)          cmd_uninstall ;;
  test)               cmd_test ;;
  enable-kernel-quirk)  enable_kernel_quirk ;;
  disable-kernel-quirk) disable_kernel_quirk ;;
  status)             cmd_status ;;
  *) echo "Usage: $0 {install|uninstall|test|enable-kernel-quirk|disable-kernel-quirk|status}"; exit 1 ;;
esac
