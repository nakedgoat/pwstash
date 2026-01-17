#!/bin/sh
# pwstash.sh — Ubuntu/Debian (old-friendly) password hash stash/restore + optional seedbox password workflow
#
# Existing behavior (kept):
#   sudo ./pwstash.sh backup <user>
#   sudo ./pwstash.sh restore <user>
#
# Added behavior:
#   sudo ./pwstash.sh --seedbox-pass [--user <user>]
#       -> backs up the user's shadow line, then runs: sudo changeseedboxpass
#
#   sudo ./pwstash.sh --restore-seedbox-pass [--user <user>]
#       -> restores the user's shadow line (ONLY when you explicitly run this switch)
#
# Notes:
# - This script does NOT auto-restore. Restore ONLY happens with --restore-seedbox-pass (or legacy "restore" cmd).
# - Backups stored in /root/pwstash/user_hashes/<user>.shadowline
#
set -eu

BASE_DIR="/root/pwstash"
HASH_DIR="$BASE_DIR/user_hashes"
STAMP="$(date +%Y%m%d_%H%M%S)"

die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || die "Run as root (use sudo)."
}

ensure_dirs() {
  mkdir -p "$HASH_DIR"
  chmod 700 "$BASE_DIR" "$HASH_DIR"
}

fix_perms() {
  chown root:root /etc/passwd
  chmod 644 /etc/passwd
  chown root:shadow /etc/shadow
  chmod 640 /etc/shadow
}

user_exists() {
  getent passwd "$1" >/dev/null 2>&1
}

default_target_user() {
  # Prefer the user who invoked sudo (not root). Fallback to current user.
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    echo "$SUDO_USER"
  else
    id -un
  fi
}

backup_user_shadowline() {
  user="$1"
  user_exists "$user" || die "User '$user' not found."

  line="$(grep "^$user:" /etc/shadow 2>/dev/null || true)"
  [ -n "$line" ] || die "No /etc/shadow entry found for '$user'."

  out="$HASH_DIR/$user.shadowline"
  umask 077
  printf "%s\n" "$line" > "$out"
  echo "Saved hash line for '$user' to: $out"
}

restore_user_shadowline() {
  user="$1"
  in="$HASH_DIR/$user.shadowline"
  [ -f "$in" ] || die "No saved hash for '$user' at: $in (run backup first)."

  new_line="$(cat "$in")"
  case "$new_line" in
    "$user":*) : ;;
    *) die "Saved line in $in doesn't look like a shadow line for '$user'." ;;
  esac

  umask 077
  cp /etc/shadow "$BASE_DIR/shadow.before_restore.$STAMP" || die "Failed to backup /etc/shadow"

  tmp="/etc/shadow.pwstash.$$"
  awk -v u="$user" -v nl="$new_line" '
    BEGIN { replaced=0 }
    $0 ~ ("^"u":") { print nl; replaced=1; next }
    { print }
    END { if (!replaced) exit 2 }
  ' /etc/shadow > "$tmp" || {
    rc=$?
    rm -f "$tmp"
    [ "$rc" -eq 2 ] && die "User '$user' not found in current /etc/shadow (won't insert automatically)."
    die "Failed to build new shadow file."
  }

  mv "$tmp" /etc/shadow
  fix_perms
  echo "Restored password hash for '$user'."
  echo "Backup of prior /etc/shadow: $BASE_DIR/shadow.before_restore.$STAMP"
}

run_seedbox_pass() {
  user="$1"

  # Backup first (so restore is possible later)
  backup_user_shadowline "$user"

  # Ensure command exists
  command -v changeseedboxpass >/dev/null 2>&1 || die "changeseedboxpass not found in PATH."

  echo "Running: sudo changeseedboxpass"
  # We are already root via sudo, but keep 'sudo' for your requested behavior.
  sudo changeseedboxpass
  echo "Done."
  echo "If you need to revert later, run:"
  echo "  sudo ./pwstash.sh --restore-seedbox-pass --user $user"
}

usage() {
  cat <<EOF
pwstash.sh — stash/restore password hashes + seedbox pass helper

Legacy commands (unchanged):
  sudo ./pwstash.sh backup <user>
  sudo ./pwstash.sh restore <user>

New switches:
  sudo ./pwstash.sh --seedbox-pass [--user <user>]
      Backup <user>'s /etc/shadow line, then run: sudo changeseedboxpass

  sudo ./pwstash.sh --restore-seedbox-pass [--user <user>]
      Restore <user>'s old password hash from the saved backup

Defaults:
  --user defaults to the sudo-invoking user (SUDO_USER) if present, else current user.

Where backups go:
  $HASH_DIR/<user>.shadowline
EOF
}

# ---- Main arg handling ----
need_root
ensure_dirs

# If first arg is legacy command
if [ $# -ge 1 ]; then
  case "$1" in
    backup)
      [ $# -eq 2 ] || die "Usage: $0 backup <user>"
      backup_user_shadowline "$2"
      exit 0
      ;;
    restore)
      [ $# -eq 2 ] || die "Usage: $0 restore <user>"
      restore_user_shadowline "$2"
      exit 0
      ;;
  esac
fi

# Switch-based mode
ACTION=""
TARGET_USER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --seedbox-pass)
      ACTION="seedbox"
      shift
      ;;
    --restore-seedbox-pass)
      ACTION="restore_seedbox"
      shift
      ;;
    --user)
      shift
      [ $# -gt 0 ] || die "--user requires a username"
      TARGET_USER="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1 (use --help)"
      ;;
  esac
done

[ -n "$ACTION" ] || { usage; exit 1; }

if [ -z "$TARGET_USER" ]; then
  TARGET_USER="$(default_target_user)"
fi

user_exists "$TARGET_USER" || die "User '$TARGET_USER' not found."

case "$ACTION" in
  seedbox)
    run_seedbox_pass "$TARGET_USER"
    ;;
  restore_seedbox)
    restore_user_shadowline "$TARGET_USER"
    ;;
  *)
    die "Internal error: unknown action '$ACTION'"
    ;;
esac
