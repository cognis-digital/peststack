# shellcheck shell=bash
# peststack — manifest parsing
# Maintainer: Cognis Digital
#
# Manifest format (pure-bash parsed, no eval of file contents):
#
#   Records are separated by one or more blank lines. Within a record, each
#   line is a "KEY = VALUE" pair. Keys are case-insensitive. Lines beginning
#   with '#' are comments. Recognized keys:
#
#     name      (required)  unique short identifier, e.g. nmap
#     category  (required)  recon|scanning|web|reporting|...  (free-form)
#     method    (required)  one of: apt pip go git
#     package   (optional)  package/module/import path; defaults to name
#     version   (optional)  pinned version string
#     desc      (optional)  human description
#
# Parsed records are exposed as parallel arrays:
#   PS_NAME[i] PS_CATEGORY[i] PS_METHOD[i] PS_PACKAGE[i] PS_VERSION[i] PS_DESC[i]
# with PS_RECORD_COUNT holding the number of records.

if [ -n "${PESTSTACK_MANIFEST_SOURCED:-}" ]; then
  return 0 2>/dev/null || true
fi
PESTSTACK_MANIFEST_SOURCED=1

# Parallel arrays populated by ps_parse_manifest.
declare -a PS_NAME PS_CATEGORY PS_METHOD PS_PACKAGE PS_VERSION PS_DESC
PS_RECORD_COUNT=0

# ps_reset_manifest — clear parsed state (useful between files / in tests).
ps_reset_manifest() {
  PS_NAME=(); PS_CATEGORY=(); PS_METHOD=(); PS_PACKAGE=()
  PS_VERSION=(); PS_DESC=()
  PS_RECORD_COUNT=0
}

# Internal: lowercase a string without external tools.
_ps_lower() {
  local s="$1" out="" c i
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [A-Z]) printf -v c '%s' "$(printf '%s' "$c" | tr 'A-Z' 'a-z')" ;;
    esac
    out="$out$c"
  done
  printf '%s' "$out"
}

# Internal: commit the current accumulator into the arrays if non-empty.
# Uses caller-scoped nameref-free temp vars passed by name via globals.
_ps_commit_record() {
  # Reads _rec_name _rec_category _rec_method _rec_package _rec_version _rec_desc
  # Returns 1 (and leaves nothing committed) if the record is entirely empty.
  if [ -z "$_rec_name$_rec_category$_rec_method$_rec_package$_rec_version$_rec_desc" ]; then
    return 1
  fi
  local idx=$PS_RECORD_COUNT
  PS_NAME[idx]="$_rec_name"
  PS_CATEGORY[idx]="$_rec_category"
  PS_METHOD[idx]="$_rec_method"
  # package defaults to name when unset
  if [ -n "$_rec_package" ]; then
    PS_PACKAGE[idx]="$_rec_package"
  else
    PS_PACKAGE[idx]="$_rec_name"
  fi
  PS_VERSION[idx]="$_rec_version"
  PS_DESC[idx]="$_rec_desc"
  PS_RECORD_COUNT=$((PS_RECORD_COUNT + 1))
  return 0
}

# ps_parse_manifest <file>
# Populates the PS_* arrays. Returns non-zero only on unreadable file or a
# structurally unparseable line (a non-blank, non-comment line lacking '=').
# Field-level validation (required/known/unique) lives in lib/validate.sh.
ps_parse_manifest() {
  local file="$1"
  [ -n "$file" ] || { ps_err "ps_parse_manifest: no file given"; return 2; }
  [ -f "$file" ] || { ps_err "manifest not found: $file"; return 2; }
  [ -r "$file" ] || { ps_err "manifest not readable: $file"; return 2; }

  ps_reset_manifest

  local _rec_name="" _rec_category="" _rec_method="" \
        _rec_package="" _rec_version="" _rec_desc=""
  local line raw key val lkey lineno=0 rc=0

  while IFS= read -r raw || [ -n "$raw" ]; do
    lineno=$((lineno + 1))
    line="$(ps_trim "$raw")"

    # Blank line => record separator.
    if [ -z "$line" ]; then
      _ps_commit_record || true
      _rec_name=""; _rec_category=""; _rec_method=""
      _rec_package=""; _rec_version=""; _rec_desc=""
      continue
    fi

    # Comment line.
    case "$line" in
      \#*) continue ;;
    esac

    # Must be KEY=VALUE.
    case "$line" in
      *=*) : ;;
      *)
        ps_err "manifest parse error at line $lineno: expected KEY=VALUE: $line"
        rc=3
        continue
        ;;
    esac

    key="$(ps_trim "${line%%=*}")"
    val="$(ps_trim "${line#*=}")"
    lkey="$(_ps_lower "$key")"

    case "$lkey" in
      name)     _rec_name="$val" ;;
      category) _rec_category="$val" ;;
      method)   _rec_method="$(_ps_lower "$val")" ;;
      package)  _rec_package="$val" ;;
      version)  _rec_version="$val" ;;
      desc|description) _rec_desc="$val" ;;
      *)
        ps_warn "unknown key '$key' at line $lineno (ignored)"
        ;;
    esac
  done < "$file"

  # Commit trailing record (file may not end with a blank line).
  _ps_commit_record || true

  return "$rc"
}
