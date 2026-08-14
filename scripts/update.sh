#!/usr/bin/env bash
set -euo pipefail

readonly GITHUB_REPO="vexa-ai/vexa"
readonly FLAKE_FILE="flake.nix"

log_info() { printf '[INFO] %s\n' "$1"; }
log_warn() { printf '[WARN] %s\n' "$1"; }
log_error() { printf '[ERROR] %s\n' "$1" >&2; }

ensure_tools() {
  local tool
  for tool in gh jq nix sed; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      log_error "$tool is required"
      exit 1
    fi
  done
}

current_revision() {
  sed -n 's/.*vexaRev = "\([^"]*\)";.*/\1/p' "$FLAKE_FILE" | head -1
}

latest_revision() {
  gh api "repos/${GITHUB_REPO}/commits/main" --jq .sha
}

source_hash() {
  local revision="$1"
  nix store prefetch-file --json --unpack \
    "https://github.com/${GITHUB_REPO}/archive/${revision}.tar.gz" \
    | jq -r .hash
}

update_flake() {
  local revision="$1"
  local hash="$2"
  sed -i "s|vexaRev = \"[^\"]*\";|vexaRev = \"${revision}\";|" "$FLAKE_FILE"
  sed -i "s|vexaHash = \"[^\"]*\";|vexaHash = \"${hash}\";|" "$FLAKE_FILE"
}

usage() {
  cat <<'EOF'
Usage: ./scripts/update.sh [--check] [--rev REVISION]

Update the pinned Vexa source revision and its Nix content hash.

  --check          Exit 1 when main has a newer revision.
  --rev REVISION  Update to an explicit commit instead of main.
EOF
}

main() {
  local check_only=false
  local requested_revision=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check)
        check_only=true
        shift
        ;;
      --rev)
        [[ $# -ge 2 ]] || { log_error "--rev needs a commit"; exit 1; }
        requested_revision="$2"
        shift 2
        ;;
      --help)
        usage
        return 0
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        return 1
        ;;
    esac
  done

  ensure_tools
  local current
  current="$(current_revision)"
  local target="${requested_revision:-$(latest_revision)}"
  log_info "Current revision: $current"
  log_info "Target revision:  $target"

  if [[ "$current" == "$target" ]]; then
    log_info "Already up to date."
    return 0
  fi

  if [[ "$check_only" == true ]]; then
    log_warn "Update available: $current -> $target"
    return 1
  fi

  local hash
  hash="$(source_hash "$target")"
  log_info "Source hash: $hash"
  update_flake "$target" "$hash"

  nix flake lock
  nix build .#vexa-source
  log_info "Updated and verified Vexa $target."
}

main "$@"
