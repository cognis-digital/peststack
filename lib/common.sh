# shellcheck shell=bash
# peststack — common helpers
# Maintainer: Cognis Digital
#
# This file is meant to be sourced. It provides logging, error handling,
# and the authorized-use banner shared across peststack subcommands.

# Guard against double-sourcing.
if [ -n "${PESTSTACK_COMMON_SOURCED:-}" ]; then
  return 0 2>/dev/null || true
fi
PESTSTACK_COMMON_SOURCED=1

PESTSTACK_VERSION="1.0.0"
PESTSTACK_MAINTAINER="Cognis Digital"

# Known install methods. Extend here if a new provisioning backend is added.
PESTSTACK_KNOWN_METHODS="apt pip go git"

# Known categories used for documentation / list grouping. Validation does not
# reject unknown categories (categories are free-form), but these are surfaced
# in help and used for ordering.
PESTSTACK_KNOWN_CATEGORIES="recon scanning web exploitation post reporting wireless mobile"

# --- logging -----------------------------------------------------------------

ps_log()  { printf '%s\n' "$*" >&2; }
ps_info() { printf '[peststack] %s\n' "$*" >&2; }
ps_warn() { printf '[peststack] WARN: %s\n' "$*" >&2; }
ps_err()  { printf '[peststack] ERROR: %s\n' "$*" >&2; }

# ps_die <message> [exit_code]
ps_die() {
  ps_err "${1:-fatal error}"
  exit "${2:-1}"
}

# --- authorized-use banner ---------------------------------------------------

# Emitted to stderr for the human-facing CLI, and embedded verbatim into any
# generated artifact (installer / Dockerfile) so the authorization context
# travels with the output.
ps_authorized_banner() {
  cat <<'BANNER'
==============================================================================
 peststack — security-assessment toolkit orchestrator
 AUTHORIZED USE ONLY. This tool provisions a penetration-testing toolkit
 environment for engagements you are explicitly authorized to perform.
 It generates installer scripts and Dockerfiles; it does not exploit,
 attack, or access any system. Using security tools against systems you do
 not own or lack written permission to test may be illegal. You are solely
 responsible for operating within the scope of your authorization and the law.
==============================================================================
BANNER
}

# Same banner as shell comment lines, for embedding into generated scripts.
ps_authorized_banner_commented() {
  ps_authorized_banner | sed 's/^/# /'
}

# --- small utilities ---------------------------------------------------------

# ps_trim <string> — strip leading/trailing whitespace.
ps_trim() {
  local s="$1"
  # remove leading whitespace
  s="${s#"${s%%[![:space:]]*}"}"
  # remove trailing whitespace
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# ps_in_list <needle> <space-separated-haystack>
ps_in_list() {
  local needle="$1" item
  shift
  for item in $1; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}
