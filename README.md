# peststack

A declarative orchestrator for assembling a **reproducible penetration-testing /
security-assessment toolkit environment**. You declare the tools you want in a
plain-text manifest; peststack validates it, generates an idempotent installer
script (or a reproducible Dockerfile), and lets you list the toolkit by
category.

peststack is pure Bash with a modular `lib/` of sourced functions and a
self-contained test suite. It installs nothing on its own — it **produces**
installer artifacts you review and run on a provisioning host you control.

- Maintainer: **Cognis Digital**
- License: **COCL 1.0**

---

## ⚠ Authorized use only

peststack is intended **solely** for provisioning tooling used in security
assessments and penetration tests that you are **explicitly authorized** to
perform. It validates a manifest, generates installer scripts and Dockerfiles,
and lists tools. **It does not exploit, attack, scan, or access any system.**

Using security tools against systems you do not own or lack written permission
to test may be illegal. You are solely responsible for operating within the
scope of your authorization and applicable law. Every artifact peststack emits
carries this notice as a banner.

---

## Install

No installation step — clone the repo and run the script with Bash 4+:

```bash
bash peststack.sh --help
```

Make it executable if you prefer:

```bash
chmod +x peststack.sh
./peststack.sh --help
```

## Quick start

```bash
# 1. Validate a manifest (required fields, known methods, unique names)
bash peststack.sh validate --manifest examples/manifest.conf

# 2. List the declared toolkit, optionally by category
bash peststack.sh list --manifest examples/manifest.conf
bash peststack.sh list --manifest examples/manifest.conf --category recon

# 3. Generate an idempotent installer script
bash peststack.sh generate --manifest examples/manifest.conf --out setup.sh

# 4. ...or a reproducible Dockerfile instead
bash peststack.sh generate --manifest examples/manifest.conf --dockerfile --out Dockerfile
```

## Commands

| Command    | Purpose |
|------------|---------|
| `validate` | Check the manifest for required fields, known install methods, and unique tool names. Exits non-zero on any error. |
| `generate` | Emit an idempotent bash installer (default) or, with `--dockerfile`, a reproducible Dockerfile. Writes to stdout unless `--out` is given. |
| `list`     | List tools grouped by category, or only those in a single `--category`. |
| `--help`   | Show usage, including the authorized-use note. |

## Manifest format

A manifest is a plain-text file of **records separated by blank lines**. Each
line within a record is a `KEY = VALUE` pair (keys are case-insensitive). Lines
beginning with `#` are comments. The file is parsed in pure Bash — its contents
are never `eval`'d or sourced.

| Key        | Required | Meaning |
|------------|:--------:|---------|
| `name`     | ✓ | Unique short identifier (letters, digits, `. _ + -`), e.g. `nmap`. |
| `category` | ✓ | Phase/group label, e.g. `recon`, `scanning`, `web`, `reporting`. Free-form. |
| `method`   | ✓ | Install backend: one of `apt`, `pip`, `go`, `git`. |
| `package`  |   | Package / module / import path / repo URL. Defaults to `name`. |
| `version`  |   | Pinned version (apt `=ver`, pip `==ver`, go `@ver`, git branch/tag). |
| `desc`     |   | Human-readable description. |

Example record:

```ini
name     = subfinder
category = recon
method   = go
package  = github.com/projectdiscovery/subfinder/v2/cmd/subfinder
version  = v2.6.6
desc     = Passive subdomain enumeration
```

See [`examples/manifest.conf`](examples/manifest.conf) for a complete, authored
manifest spanning several categories.

## What the generated artifacts look like

**Installer (`generate`)** — a `set -euo pipefail` bash script that:

- opens with the authorized-use banner as comments,
- refreshes the apt index once if any apt tool is declared,
- defines and calls one `install_<tool>` function per tool,
- guards each install behind a **presence check** so re-runs are idempotent
  (`command -v`, `python3 -c "import ..."`, or a clone-dir check),
- emits a per-method install command honoring any pinned version.

**Dockerfile (`generate --dockerfile`)** — a reproducible image that:

- starts `FROM debian:stable-slim`,
- installs only the base prerequisites the manifest actually needs,
- batches apt tools into a single layer,
- adds one `RUN` per pip / go / git tool.

> The generated installer is meant to be **reviewed before running** on a
> provisioning host you control. peststack itself runs none of these commands.

## Install methods

| Method | Install form | Presence check |
|--------|--------------|----------------|
| `apt`  | `apt-get install -y --no-install-recommends pkg[=ver]` | `command -v name` |
| `pip`  | `pip3 install --no-cache-dir pkg[==ver]` | importable module / console script |
| `go`   | `go install pkg@{ver,latest}` | `command -v name` |
| `git`  | `git clone --depth 1 [--branch ver] url $PESTSTACK_SRC/name` | clone dir has `.git` |

## Project layout

```
peststack/
├── peststack.sh            # CLI entrypoint (validate / generate / list)
├── lib/
│   ├── common.sh           # logging, authorized-use banner, helpers
│   ├── manifest.sh         # pure-bash manifest parser -> PS_* arrays
│   ├── validate.sh         # required/known/unique field validation
│   ├── generate.sh         # installer + Dockerfile emitters
│   └── list.sh             # category-grouped inventory rendering
├── examples/
│   └── manifest.conf       # authored example toolkit manifest
├── tests/
│   └── run.sh              # self-contained test suite (installs nothing)
├── .github/workflows/ci.yml
├── .gitignore
└── README.md
```

## Tests

The suite is plain Bash and **installs nothing** — it only exercises validate /
generate / list logic over crafted manifests and asserts on the emitted text.

```bash
bash tests/run.sh
```

It prints a `RESULT: N passed, M failed` line and exits non-zero on any failure.

## Continuous integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on Ubuntu: it
shellchecks the scripts when ShellCheck is available, then runs the test suite.

## License

License: **COCL 1.0**. See the canonical COCL text distributed with the Cognis
Digital suite.
