#!/usr/bin/env bash
# Manage SOPS-encrypted volsync (kopia) secrets without exposing secret values.
#
# All apps back up to a single shared kopia repository
# (KOPIA_REPOSITORY=filesystem:///mnt/repository) using one shared
# KOPIA_PASSWORD that is copied into each namespace as a `volsync-secret`.
# Because the repository is shared, every namespace's secret must carry the
# SAME credentials -- a per-app random password cannot open the shared repo.
#
#   sync   : copy KOPIA_REPOSITORY + KOPIA_PASSWORD from a known-good reference
#            secret into one or more targets (repair a broken/missing secret,
#            or onboard a new namespace).
#   rotate : generate ONE new password and write it into all given targets at
#            once. The live repo password must be changed too (see note printed
#            after a rotate) or existing backups become unreadable.
#
# Secret values are NEVER written to stdout -- only paths, lengths and short
# one-way digests (for consistency checks). Safe to run unattended / on behalf
# of an agent without leaking material into a transcript.
set -euo pipefail
umask 077

die()  { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }
need sops; need yq; need openssl; need sha256sum; need mktemp

usage() {
  cat >&2 <<'EOF'
Usage:
  volsync-secret.sh sync   --reference <good-secret.yaml> <target-secret.yaml>...
  volsync-secret.sh rotate <target-secret.yaml>... [--bytes N]

sync    Copy the shared kopia credentials from --reference into each target.
        The target's namespace is taken from its parent directory name.
        Use this to repair openviking's corrupt secret or seed a new one.

rotate  Generate one new KOPIA_PASSWORD (openssl, N hex bytes; default 32) and
        write it -- together with each target's existing KOPIA_REPOSITORY --
        into every target. Does NOT change the password on the repo itself.

Examples:
  # Repair openviking + onboard hermes from the shared (media) creds:
  scripts/volsync-secret.sh sync --reference apps/production/apps/media/volsync-secret.yaml \
      apps/production/apps/openviking/volsync-secret.yaml \
      apps/production/apps/hermes/volsync-secret.yaml

  # Rotate the shared password across every namespace that holds it:
  scripts/volsync-secret.sh rotate $(git ls-files '**/volsync-secret.yaml')
EOF
  exit 2
}

short_sha() { printf %s "$1" | sha256sum | cut -c1-12; }

# Read a kopia field from a sops file, tolerating either stringData (plain) or
# data (base64) encoding. Prints the decrypted value to stdout (callers capture
# it into a variable -- it is never echoed by this script).
read_field() { # $1=file  $2=KEY
  sops -d "$1" 2>/dev/null | yq -r "(.stringData.$2 // (.data.$2 | @base64d)) // \"\"" 2>/dev/null
}

# Author one encrypted secret. Plaintext lives only in a 0600 tempfile that is
# removed on return; nothing sensitive is printed.
write_secret() { # $1=target  $2=repo  $3=password
  local target="$1" repo="$2" pw="$3" ns tmp wrepo wpw
  [ -n "$repo" ] || die "refusing to write empty KOPIA_REPOSITORY for $target"
  [ -n "$pw" ]   || die "refusing to write empty KOPIA_PASSWORD for $target"
  case "$target" in
    *apps/*) : ;;  # under apps/ so .sops.yaml creation_rules match
    *) echo "  warn: $target is not under apps/; .sops.yaml rules may not apply" >&2 ;;
  esac
  ns=$(basename "$(dirname "$target")")
  tmp=$(mktemp)
  trap 'rm -f "$tmp" "${target}.enc.tmp"' RETURN
  cat > "$tmp" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: volsync-secret
  namespace: ${ns}
type: Opaque
stringData:
  KOPIA_REPOSITORY: "${repo}"
  KOPIA_PASSWORD: "${pw}"
EOF
  # --filename-override makes sops apply the creation_rule for the *target*
  # path even though it is reading from a tempfile elsewhere.
  sops --encrypt --filename-override "$target" "$tmp" > "${target}.enc.tmp"
  mv "${target}.enc.tmp" "$target"

  # Non-leaking verification: decrypt the result and confirm it round-trips.
  wrepo=$(read_field "$target" KOPIA_REPOSITORY)
  wpw=$(read_field "$target" KOPIA_PASSWORD)
  [ "$wrepo" = "$repo" ] || die "verify failed: KOPIA_REPOSITORY mismatch in $target"
  [ "$wpw"   = "$pw"   ] || die "verify failed: KOPIA_PASSWORD mismatch in $target"
  printf "  wrote %-58s ns=%-14s repo=%s pwLen=%s pwSha=%s\n" \
    "$target" "$ns" "$repo" "${#pw}" "$(short_sha "$pw")"
}

[ $# -ge 1 ] || usage
mode="$1"; shift

case "$mode" in
  sync)
    ref=""; targets=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --reference) ref="${2:-}"; shift 2 ;;
        -h|--help)   usage ;;
        --*)         die "unknown flag: $1" ;;
        *)           targets+=("$1"); shift ;;
      esac
    done
    [ -n "$ref" ]            || die "sync requires --reference <good-secret.yaml>"
    [ -f "$ref" ]           || die "reference not found: $ref"
    [ ${#targets[@]} -ge 1 ] || die "sync requires at least one target"
    repo=$(read_field "$ref" KOPIA_REPOSITORY)
    pw=$(read_field "$ref" KOPIA_PASSWORD)
    { [ -n "$repo" ] && [ -n "$pw" ]; } || \
      die "could not read KOPIA_* from $ref (decrypt failed or unexpected keys)"
    echo "sync: shared creds from $ref (repo=$repo, pwSha=$(short_sha "$pw")) -> ${#targets[@]} target(s):"
    for t in "${targets[@]}"; do write_secret "$t" "$repo" "$pw"; done
    echo "done. commit the encrypted file(s); Flux will reconcile."
    ;;

  rotate)
    bytes=32; targets=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --bytes)   bytes="${2:-}"; shift 2 ;;
        -h|--help) usage ;;
        --*)       die "unknown flag: $1" ;;
        *)         targets+=("$1"); shift ;;
      esac
    done
    [ ${#targets[@]} -ge 1 ] || die "rotate requires at least one target"
    [[ "$bytes" =~ ^[0-9]+$ ]] || die "--bytes must be an integer"
    newpw=$(openssl rand -hex "$bytes")   # hex => sed/YAML-safe, no locale issues
    echo "rotate: new shared password (len=${#newpw}, pwSha=$(short_sha "$newpw")) -> ${#targets[@]} target(s):"
    for t in "${targets[@]}"; do
      repo=$(read_field "$t" KOPIA_REPOSITORY)
      [ -n "$repo" ] || die "cannot read existing KOPIA_REPOSITORY for $t; seed it first with 'sync --reference'"
      write_secret "$t" "$repo" "$newpw"
    done
    cat <<'EOF'

NOTE: the kopia repository password on the repo itself was NOT changed.
Existing backups remain readable only with the OLD password until you run,
in-cluster where filesystem:///mnt/repository is mounted:
    kopia repository change-password
Do that atomically with committing these secrets, or restores will break.
EOF
    ;;

  -h|--help) usage ;;
  *)         usage ;;
esac
