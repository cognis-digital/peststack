#!/usr/bin/env bash
# peststack — declarative orchestrator for assembling a reproducible
# penetration-testing / security-assessment toolkit environment.
#
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# AUTHORIZED USE ONLY. peststack provisions a toolkit environment for
# engagements you are explicitly authorized to perform. It validates a
# manifest, generates an idempotent installer script or a reproducible
# Dockerfile, and lists tools by category. It does NOT exploit, attack, or
# access any system.

set -euo pipefail

# Resolve our own directory so lib/ is found regardless of CWD.
PESTSTACK_SELF="${BASH_SOURCE[0]}"
while [ -h "$PESTSTACK_SELF" ]; do
  _dir="$(cd -P "$(dirname "$PESTSTACK_SELF")" && pwd)"
  PESTSTACK_SELF="$(readlink "$PESTSTACK_SELF")"
  case "$PESTSTACK_SELF" in
    /*) : ;;
    *) PESTSTACK_SELF="$_dir/$PESTSTACK_SELF" ;;
  esac
done
PESTSTACK_DIR="$(cd -P "$(dirname "$PESTSTACK_SELF")" && pwd)"
PESTSTACK_LIB="$PESTSTACK_DIR/lib"

# shellcheck source=lib/common.sh
. "$PESTSTACK_LIB/common.sh"
# shellcheck source=lib/manifest.sh
. "$PESTSTACK_LIB/manifest.sh"
# shellcheck source=lib/validate.sh
. "$PESTSTACK_LIB/validate.sh"
# shellcheck source=lib/generate.sh
. "$PESTSTACK_LIB/generate.sh"
# shellcheck source=lib/list.sh
. "$PESTSTACK_LIB/list.sh"

usage() {
  cat <<USAGE
peststack $PESTSTACK_VERSION — security-assessment toolkit orchestrator
Maintainer: $PESTSTACK_MAINTAINER   License: COCL 1.0

AUTHORIZED USE ONLY. This tool provisions a penetration-testing toolkit
environment for engagements you are explicitly authorized to perform. It
generates installer scripts and Dockerfiles; it does not exploit anything.

USAGE:
  peststack.sh <command> [options]

COMMANDS:
  validate   --manifest <file>
             Check the manifest for required fields, known install methods,
             and unique tool names. Exits non-zero on any error.

  generate   --manifest <file> [--out <file>] [--dockerfile]
             Emit an idempotent bash installer (default) or, with
             --dockerfile, a reproducible Dockerfile. Writes to stdout
             unless --out is given.

  list       --manifest <file> [--category <name>]
             List tools grouped by category, or only those in one category.

  --help | -h
             Show this help.

INSTALL METHODS:  $PESTSTACK_KNOWN_METHODS
EXAMPLE MANIFEST: $PESTSTACK_DIR/examples/manifest.conf

EXAMPLES:
  peststack.sh validate --manifest examples/manifest.conf
  peststack.sh generate --manifest examples/manifest.conf --out setup.sh
  peststack.sh generate --manifest examples/manifest.conf --dockerfile --out Dockerfile
  peststack.sh list     --manifest examples/manifest.conf --category recon
USAGE
}

# Parse a --manifest value out of the remaining args; sets MANIFEST.
# Generic option scanning is done per-command below.

cmd_validate() {
  local manifest=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --manifest) manifest="${2:-}"; shift 2 ;;
      --manifest=*) manifest="${1#*=}"; shift ;;
      -h|--help) usage; return 0 ;;
      *) ps_die "validate: unexpected argument '$1'" 2 ;;
    esac
  done
  [ -n "$manifest" ] || ps_die "validate: --manifest <file> is required" 2

  ps_parse_manifest "$manifest" || ps_die "failed to parse manifest" 1
  if ps_validate_manifest; then
    ps_info "manifest OK: $PS_RECORD_COUNT tool(s), no errors."
    return 0
  fi
  return 1
}

cmd_generate() {
  local manifest="" out="" mode="installer"
  while [ $# -gt 0 ]; do
    case "$1" in
      --manifest) manifest="${2:-}"; shift 2 ;;
      --manifest=*) manifest="${1#*=}"; shift ;;
      --out) out="${2:-}"; shift 2 ;;
      --out=*) out="${1#*=}"; shift ;;
      --dockerfile) mode="dockerfile"; shift ;;
      -h|--help) usage; return 0 ;;
      *) ps_die "generate: unexpected argument '$1'" 2 ;;
    esac
  done
  [ -n "$manifest" ] || ps_die "generate: --manifest <file> is required" 2

  ps_parse_manifest "$manifest" || ps_die "failed to parse manifest" 1
  ps_validate_manifest || ps_die "refusing to generate from an invalid manifest" 1

  local render
  if [ "$mode" = "dockerfile" ]; then
    render=ps_generate_dockerfile
  else
    render=ps_generate_installer
  fi

  if [ -n "$out" ]; then
    "$render" > "$out"
    [ "$mode" = "installer" ] && chmod +x "$out" 2>/dev/null || true
    ps_info "wrote $mode to $out"
  else
    "$render"
  fi
  return 0
}

cmd_list() {
  local manifest="" category=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --manifest) manifest="${2:-}"; shift 2 ;;
      --manifest=*) manifest="${1#*=}"; shift ;;
      --category) category="${2:-}"; shift 2 ;;
      --category=*) category="${1#*=}"; shift ;;
      -h|--help) usage; return 0 ;;
      *) ps_die "list: unexpected argument '$1'" 2 ;;
    esac
  done
  [ -n "$manifest" ] || ps_die "list: --manifest <file> is required" 2

  ps_parse_manifest "$manifest" || ps_die "failed to parse manifest" 1
  # Listing does not hard-require validity, but warn the user if invalid.
  ps_validate_manifest || ps_warn "manifest has validation errors (listing anyway)"

  ps_list_tools "$category"
}

main() {
  if [ $# -eq 0 ]; then
    usage
    exit 2
  fi

  local cmd="$1"; shift
  case "$cmd" in
    validate) cmd_validate "$@" ;;
    generate) cmd_generate "$@" ;;
    list)     cmd_list "$@" ;;
    -h|--help|help) usage ;;
    --version|version) printf 'peststack %s\n' "$PESTSTACK_VERSION" ;;
    *)
      ps_err "unknown command: $cmd"
      usage
      exit 2
      ;;
  esac
}

main "$@"
