# shellcheck shell=bash
# peststack — listing / inventory
# Maintainer: Cognis Digital
#
# Renders the parsed PS_* arrays to stdout, optionally filtered by category.

if [ -n "${PESTSTACK_LIST_SOURCED:-}" ]; then
  return 0 2>/dev/null || true
fi
PESTSTACK_LIST_SOURCED=1

# ps_list_tools [category]
# With no argument, lists every tool grouped by category. With a category,
# lists only matching tools. Returns non-zero if a category filter matches
# nothing (so callers/scripts can detect an empty selection).
ps_list_tools() {
  local filter="${1:-}"
  local i printed=0

  if [ -n "$filter" ]; then
    printf 'Tools in category: %s\n' "$filter"
    printf '%s\n' "----------------------------------------"
    for (( i=0; i<PS_RECORD_COUNT; i++ )); do
      [ "${PS_CATEGORY[i]}" = "$filter" ] || continue
      _ps_print_tool_row "$i"
      printed=$((printed + 1))
    done
    if [ "$printed" -eq 0 ]; then
      ps_warn "no tools found in category '$filter'"
      return 1
    fi
    printf '\n%d tool(s).\n' "$printed"
    return 0
  fi

  # Grouped listing: known categories in canonical order first, then any
  # remaining categories encountered in the manifest.
  local cat seen_cats="" c
  printf 'peststack toolkit inventory (%d tool(s))\n' "$PS_RECORD_COUNT"
  printf '%s\n' "========================================"

  for cat in $PESTSTACK_KNOWN_CATEGORIES; do
    _ps_emit_category_group "$cat" && seen_cats="$seen_cats $cat"
  done

  # Trailing groups for categories not in the known list.
  for (( i=0; i<PS_RECORD_COUNT; i++ )); do
    c="${PS_CATEGORY[i]}"
    ps_in_list "$c" "$seen_cats" && continue
    ps_in_list "$c" "$PESTSTACK_KNOWN_CATEGORIES" && continue
    _ps_emit_category_group "$c"
    seen_cats="$seen_cats $c"
  done

  return 0
}

# Internal: print all tools in one category as a titled group.
# Returns 0 if the group had at least one tool, 1 otherwise.
_ps_emit_category_group() {
  local cat="$1" i found=0
  for (( i=0; i<PS_RECORD_COUNT; i++ )); do
    [ "${PS_CATEGORY[i]}" = "$cat" ] || continue
    if [ "$found" -eq 0 ]; then
      printf '\n[%s]\n' "$cat"
      found=1
    fi
    _ps_print_tool_row "$i"
  done
  [ "$found" -eq 1 ]
}

# Internal: print a single tool row.
_ps_print_tool_row() {
  local i="$1"
  local ver="${PS_VERSION[i]:-(latest)}"
  printf '  %-18s method=%-4s version=%-12s %s\n' \
    "${PS_NAME[i]}" "${PS_METHOD[i]}" "$ver" "${PS_DESC[i]}"
}
