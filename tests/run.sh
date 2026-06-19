#!/usr/bin/env bash
# peststack — self-contained test runner. Installs nothing; only exercises
# the CLI's validate / generate / list logic over crafted manifests.
# Maintainer: Cognis Digital
#
# Exits non-zero if any assertion fails.

set -uo pipefail

TESTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -P "$TESTS_DIR/.." && pwd)"
PESTSTACK="$ROOT_DIR/peststack.sh"
EXAMPLE="$ROOT_DIR/examples/manifest.conf"

PASS=0
FAIL=0
TMPDIR_T="$(mktemp -d 2>/dev/null || mktemp -d -t peststack)"
trap 'rm -rf "$TMPDIR_T"' EXIT

# --- assertion helpers -------------------------------------------------------

ok()   { PASS=$((PASS + 1)); printf '  ok   - %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL - %s\n' "$1"; }

# assert_exit <expected_code> <description> -- <command...>
assert_exit() {
  local expected="$1" desc="$2"; shift 2
  [ "$1" = "--" ] && shift
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$expected" ]; then
    ok "$desc (exit $rc)"
  else
    bad "$desc (expected exit $expected, got $rc)"
    printf '%s\n' "$out" | sed 's/^/        /'
  fi
}

# assert_zero / assert_nonzero shortcuts
assert_zero()    { assert_exit 0 "$1" -- "${@:2}"; }
assert_nonzero() {
  local desc="$1"; shift
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    ok "$desc (exit $rc)"
  else
    bad "$desc (expected non-zero, got 0)"
    printf '%s\n' "$out" | sed 's/^/        /'
  fi
}

# assert_contains <description> <needle> -- <command...>
assert_contains() {
  local desc="$1" needle="$2"; shift 2
  [ "$1" = "--" ] && shift
  local out
  out="$("$@" 2>&1)" || true
  if printf '%s' "$out" | grep -qF -- "$needle"; then
    ok "$desc"
  else
    bad "$desc (missing: $needle)"
  fi
}

# assert_not_contains <description> <needle> -- <command...>
assert_not_contains() {
  local desc="$1" needle="$2"; shift 2
  [ "$1" = "--" ] && shift
  local out
  out="$("$@" 2>&1)" || true
  if printf '%s' "$out" | grep -qF -- "$needle"; then
    bad "$desc (unexpectedly found: $needle)"
  else
    ok "$desc"
  fi
}

run() { bash "$PESTSTACK" "$@"; }

# --- fixtures ----------------------------------------------------------------

make_broken_missing_field() {
  cat > "$TMPDIR_T/missing.conf" <<'EOF'
name     = nmap
category = scanning
method   = apt

# second record is missing the required 'method' field
name     = nikto
category = web
EOF
}

make_broken_unknown_method() {
  cat > "$TMPDIR_T/badmethod.conf" <<'EOF'
name     = nmap
category = scanning
method   = brew
package  = nmap
EOF
}

make_broken_dup_name() {
  cat > "$TMPDIR_T/dup.conf" <<'EOF'
name     = nmap
category = scanning
method   = apt

name     = nmap
category = web
method   = pip
EOF
}

make_minimal_valid() {
  cat > "$TMPDIR_T/min.conf" <<'EOF'
name     = nmap
category = scanning
method   = apt
package  = nmap

name     = sqlmap
category = web
method   = pip
package  = sqlmap
version  = 1.8.2

name     = amass
category = recon
method   = go
package  = github.com/owasp-amass/amass/v4/...

name     = seclists
category = recon
method   = git
package  = https://example.invalid/seclists.git
EOF
}

# =============================================================================
echo "peststack test suite"
echo "===================="

# --- 0. preconditions --------------------------------------------------------
echo "[group] preconditions"
if [ -f "$PESTSTACK" ]; then ok "entrypoint exists"; else bad "entrypoint exists"; fi
if [ -f "$EXAMPLE" ];   then ok "example manifest exists"; else bad "example manifest exists"; fi

# --- 1. help -----------------------------------------------------------------
echo "[group] help"
assert_zero     "--help exits 0"                       run --help
assert_contains "--help shows AUTHORIZED USE notice" "AUTHORIZED USE ONLY" -- run --help
assert_contains "--help shows COCL license"          "COCL 1.0"            -- run --help

# --- 2. validate: example passes --------------------------------------------
echo "[group] validate (happy path)"
assert_zero "validate passes on example manifest" run validate --manifest "$EXAMPLE"

# --- 3. validate: broken manifests fail -------------------------------------
echo "[group] validate (failure cases)"
make_broken_missing_field
make_broken_unknown_method
make_broken_dup_name

assert_nonzero "validate fails on missing required field" \
  run validate --manifest "$TMPDIR_T/missing.conf"
assert_contains "missing-field error names the field" "missing required field" -- \
  run validate --manifest "$TMPDIR_T/missing.conf"

assert_nonzero "validate fails on unknown install method" \
  run validate --manifest "$TMPDIR_T/badmethod.conf"
assert_contains "unknown-method error is reported" "unknown install method" -- \
  run validate --manifest "$TMPDIR_T/badmethod.conf"

assert_nonzero "validate fails on duplicate tool name" \
  run validate --manifest "$TMPDIR_T/dup.conf"
assert_contains "duplicate-name error is reported" "duplicate tool name" -- \
  run validate --manifest "$TMPDIR_T/dup.conf"

assert_nonzero "validate fails on missing manifest file" \
  run validate --manifest "$TMPDIR_T/does-not-exist.conf"
assert_nonzero "validate requires --manifest" run validate

# --- 4. generate installer ---------------------------------------------------
echo "[group] generate (installer)"
make_minimal_valid
MIN="$TMPDIR_T/min.conf"
SETUP="$TMPDIR_T/setup.sh"
run generate --manifest "$MIN" --out "$SETUP"

if [ -f "$SETUP" ]; then ok "installer file written"; else bad "installer file written"; fi
assert_contains "installer is bash"                   "#!/usr/bin/env bash" -- cat "$SETUP"
assert_contains "installer has authorized-use banner" "AUTHORIZED USE ONLY" -- cat "$SETUP"
assert_contains "installer uses set -euo pipefail"    "set -euo pipefail"   -- cat "$SETUP"
assert_contains "installer has idempotence guard"     "already present"     -- cat "$SETUP"
# per-method blocks
assert_contains "apt block present"  "apt-get install -y" -- cat "$SETUP"
assert_contains "pip block present"  "pip3 install"       -- cat "$SETUP"
assert_contains "pip version pin honored" "sqlmap==1.8.2" -- cat "$SETUP"
assert_contains "go block present"   "go install"         -- cat "$SETUP"
assert_contains "git block present"  "git clone"          -- cat "$SETUP"
# per-tool function + invocation
assert_contains "per-tool function for nmap"  "install_nmap()" -- cat "$SETUP"
assert_contains "per-tool function invoked"   "install_nmap"   -- cat "$SETUP"
# generated installer must itself parse as valid bash
assert_zero "generated installer is syntactically valid bash" bash -n "$SETUP"

# generate to stdout (no --out)
assert_contains "generate to stdout emits banner" "AUTHORIZED USE ONLY" -- \
  run generate --manifest "$MIN"

# refuse to generate from an invalid manifest
assert_nonzero "generate refuses invalid manifest" \
  run generate --manifest "$TMPDIR_T/dup.conf" --out "$TMPDIR_T/should-not-exist.sh"

# --- 5. generate dockerfile --------------------------------------------------
echo "[group] generate (dockerfile)"
DOCKER="$TMPDIR_T/Dockerfile"
run generate --manifest "$MIN" --dockerfile --out "$DOCKER"
if [ -f "$DOCKER" ]; then ok "Dockerfile written"; else bad "Dockerfile written"; fi
assert_contains "Dockerfile has FROM"            "FROM "              -- cat "$DOCKER"
assert_contains "Dockerfile has RUN"             "RUN "               -- cat "$DOCKER"
assert_contains "Dockerfile has banner"          "AUTHORIZED USE ONLY" -- cat "$DOCKER"
assert_contains "Dockerfile installs apt tool"   "nmap"               -- cat "$DOCKER"
assert_contains "Dockerfile pip install"         "pip3 install"       -- cat "$DOCKER"
assert_contains "Dockerfile go install"          "go install"         -- cat "$DOCKER"
assert_contains "Dockerfile git clone"           "git clone"          -- cat "$DOCKER"

# --- 6. list -----------------------------------------------------------------
echo "[group] list"
assert_zero     "list (all) exits 0"                  run list --manifest "$EXAMPLE"
assert_contains "list (all) shows a recon tool"  "amass"   -- run list --manifest "$EXAMPLE"
assert_contains "list (all) shows a web tool"    "sqlmap"  -- run list --manifest "$EXAMPLE"

# category filter includes matching, excludes non-matching
assert_contains "list --category recon includes amass"  "amass"  -- \
  run list --manifest "$EXAMPLE" --category recon
assert_not_contains "list --category recon excludes sqlmap" "sqlmap" -- \
  run list --manifest "$EXAMPLE" --category recon
assert_contains "list --category web includes nikto" "nikto" -- \
  run list --manifest "$EXAMPLE" --category web

# empty category selection returns non-zero
assert_nonzero "list of empty category is non-zero" \
  run list --manifest "$EXAMPLE" --category nonesuch

# --- 7. attribution hygiene --------------------------------------------------
echo "[group] hygiene"
assert_not_contains "installer has no Claude attribution" "Claude" -- cat "$SETUP"
assert_not_contains "Dockerfile has no Claude attribution" "Claude" -- cat "$DOCKER"

# =============================================================================
echo
echo "===================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
