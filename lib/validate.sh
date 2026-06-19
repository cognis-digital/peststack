# shellcheck shell=bash
# peststack — manifest validation
# Maintainer: Cognis Digital
#
# Validates the parsed PS_* arrays:
#   - at least one record
#   - required fields present (name, category, method)
#   - method is one of the known install methods
#   - names are unique
#   - name looks like a safe short identifier
#
# ps_validate_manifest prints human-readable errors to stderr and returns the
# number of errors capped at 1 for exit purposes (0 == clean).

if [ -n "${PESTSTACK_VALIDATE_SOURCED:-}" ]; then
  return 0 2>/dev/null || true
fi
PESTSTACK_VALIDATE_SOURCED=1

# Internal: validate a name token is a safe short identifier.
# Allowed: letters, digits, '-', '_', '.', '+'. Must be non-empty.
_ps_valid_name() {
  case "$1" in
    "" ) return 1 ;;
    *[!A-Za-z0-9._+-]* ) return 1 ;;
    * ) return 0 ;;
  esac
}

# ps_validate_manifest
# Operates on already-parsed PS_* arrays. Returns 0 if valid, 1 otherwise.
ps_validate_manifest() {
  local errors=0 i j name

  if [ "${PS_RECORD_COUNT:-0}" -eq 0 ]; then
    ps_err "manifest contains no tool records"
    return 1
  fi

  for (( i=0; i<PS_RECORD_COUNT; i++ )); do
    name="${PS_NAME[i]}"
    local label="record $((i + 1))"
    [ -n "$name" ] && label="tool '$name'"

    # Required: name
    if [ -z "${PS_NAME[i]}" ]; then
      ps_err "$label: missing required field 'name'"
      errors=$((errors + 1))
    elif ! _ps_valid_name "${PS_NAME[i]}"; then
      ps_err "$label: invalid name (allowed: letters digits . _ + -)"
      errors=$((errors + 1))
    fi

    # Required: category
    if [ -z "${PS_CATEGORY[i]}" ]; then
      ps_err "$label: missing required field 'category'"
      errors=$((errors + 1))
    fi

    # Required: method, and must be known
    if [ -z "${PS_METHOD[i]}" ]; then
      ps_err "$label: missing required field 'method'"
      errors=$((errors + 1))
    elif ! ps_in_list "${PS_METHOD[i]}" "$PESTSTACK_KNOWN_METHODS"; then
      ps_err "$label: unknown install method '${PS_METHOD[i]}' (known: $PESTSTACK_KNOWN_METHODS)"
      errors=$((errors + 1))
    fi

    # method=git typically needs a package (the repo URL). Warn, don't fail.
    if [ "${PS_METHOD[i]}" = "git" ] && [ "${PS_PACKAGE[i]}" = "${PS_NAME[i]}" ]; then
      ps_warn "$label: git method with no 'package' URL; using name as clone target"
    fi
  done

  # Uniqueness of names (O(n^2), fine for manifest sizes).
  for (( i=0; i<PS_RECORD_COUNT; i++ )); do
    [ -z "${PS_NAME[i]}" ] && continue
    for (( j=i+1; j<PS_RECORD_COUNT; j++ )); do
      if [ "${PS_NAME[i]}" = "${PS_NAME[j]}" ]; then
        ps_err "duplicate tool name '${PS_NAME[i]}' (records $((i + 1)) and $((j + 1)))"
        errors=$((errors + 1))
      fi
    done
  done

  if [ "$errors" -gt 0 ]; then
    ps_err "validation failed with $errors error(s)"
    return 1
  fi
  return 0
}
