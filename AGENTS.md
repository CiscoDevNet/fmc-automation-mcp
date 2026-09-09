<!--
Copyright 2026 Cisco Systems, Inc. and its affiliates

SPDX-License-Identifier: Apache-2.0
-->

# AGENTS.md — fmc-automation-mcp

Guidance for AI coding agents (VS Code / GitHub Copilot, Cursor, Codex, Claude Code,
Gemini CLI, etc.) working in this repository.

**What this project is.** A Cisco Secure Firewall Management Center (FMC) automation
starter pack. It performs the same six FMC tasks — inventory export, network/host
objects, service objects, access rules, manual NAT, and compliance reporting — three
ways (**Python**, **Ansible**, **Terraform**), and ships **three Model Context Protocol
servers** so an AI agent can drive that automation without being able to change a
firewall in a single unreviewed step.

**Read these before making changes:** [README.md](README.md), [SECURITY.md](SECURITY.md),
[docs/TESTING.md](docs/TESTING.md), [mcp_servers/README.md](mcp_servers/README.md).

> **This code talks to a firewall management plane.** Read
> [Safety rules for agents](#safety-rules-for-agents) before proposing, generating, or
> running anything that writes to FMC.

## Repository map

```text
fmc-automation-mcp/
├── python/          Scripts and the shared common/ package
│   ├── common/        cli.py, config.py, fmc_client.py, logger.py, utils.py
│   ├── inventory/     get_inventory.py
│   ├── objects/       validate_objects.py, create_objects.py
│   ├── services/      validate_services.py, create_services.py
│   ├── policy/        validate_rules.py, create_rules.py, get_rules.py
│   ├── nat/           validate_nat.py, create_manual_nat.py
│   └── reports/       compliance_report.py
├── ansible/         inventory.yml, group_vars/, vars/, playbooks/, requirements.yml
├── terraform/       provider.tf, versions.tf, variables.tf, main.tf, outputs.tf
├── mcp_servers/     rest-api-mcp/, ansible-mcp/, terraform-mcp/
├── inputs/          CSV templates: objects.csv, services.csv, rules.csv, nat.csv
├── outputs/         Generated reports, logs, backups — gitignored, never commit
├── docs/            TESTING.md, ADVANCED_USE_CASES.md, REFERENCES.md
└── tests/           Unit tests (no live FMC required)
```

There is **no Makefile and no task runner** — run the commands below directly.

## Dev environment tips

- **Python version**: 3.11 or later. CI runs the matrix 3.11 / 3.12 / 3.13. `ruff`
  targets `py311` and `mypy` is pinned to `python_version = "3.11"`, so do not use
  syntax newer than 3.11 in `python/` or `mcp_servers/`.
- **Virtual env (required — never `pip install` into the system interpreter)**:
  ```bash
  python3 -m venv .venv
  source .venv/bin/activate          # Windows: .venv\Scripts\Activate.ps1
  python -m pip install -U pip
  ```
- **Install runtime + dev dependencies**:
  ```bash
  pip install -r python/requirements.txt
  pip install -r requirements-dev.txt
  pre-commit install
  ```
  Runtime pins live in `python/requirements.txt` (`requests`, `python-dotenv`, `pandas`,
  `openpyxl`, `PyYAML`) and in each `mcp_servers/*/requirements.txt` (`fastmcp`, plus
  `httpx` for REST and `ansible-core` for Ansible). Dev/CI tooling lives in
  `requirements-dev.txt`. Keep runtime and dev dependencies in their own files.
- **Each MCP server is self-contained.** It has its own `requirements.txt`,
  `.env.example`, `Dockerfile`, `docker-compose.yml`, and tests. Install it from inside
  its own folder, in its own virtual env.
- **Configuration is environment based.** Copy `python/.env.example` to `python/.env`
  (gitignored) and edit it. Never hardcode a host, credential, or UUID in a script.

  | Variable | Required | Notes |
  | --- | --- | --- |
  | `FMC_HOST` | yes | `https://host-or-ip` — scheme included, **no trailing slash**, no path. Plaintext `http://` is rejected |
  | `FMC_USERNAME` / `FMC_PASSWORD` | yes | Dedicated least-privilege API user, never a shared admin account |
  | `VERIFY_SSL` | no | Defaults to `true`. **Do not suggest setting this to `false`** |
  | `FMC_CA_BUNDLE` | no | Absolute path to a PEM file — the correct way to handle a self-signed lab FMC |
  | `FMC_DOMAIN_UUID` | no | Blank auto-discovers the global domain |
  | `ACCESS_POLICY_ID` | for rule scripts | From `outputs/reports/access_policies.json` |
  | `NAT_POLICY_ID` | for NAT scripts | From FMC |
  | `OBJECTS_INPUT` / `SERVICES_INPUT` / `RULES_INPUT` / `NAT_INPUT` | no | Override the default CSV path |
  | `LOG_LEVEL` | no | `DEBUG` / `INFO` / `WARNING` / `ERROR`, defaults to `INFO` |

- **Shared client**: all FMC HTTP access goes through `python/common/fmc_client.py`. It
  owns token auth, TLS handling, redaction, and `get_all()` pagination. **Add new API
  calls there rather than opening a new `requests` session in a script.** FMC silently
  truncates large list responses, so never replace `get_all()` with a single
  `limit=1000` call.
- **CLI conventions**: every script uses `python/common/cli.py`, so it supports `--help`,
  an optional positional `input` path that defaults to the matching file in `inputs/`,
  and `--log-level`. A missing input path exits with code `2`.

### Quick run examples

Run from the repository root with the virtual env activated.

```bash
# 0. Read-only first: export inventory and find your ACCESS_POLICY_ID
python python/inventory/get_inventory.py

# 1. Network / host objects — ALWAYS validate before creating
python python/objects/validate_objects.py inputs/objects.csv
python python/objects/create_objects.py   inputs/objects.csv

# 2. Service objects
python python/services/validate_services.py inputs/services.csv
python python/services/create_services.py   inputs/services.csv

# 3. Access rules (needs ACCESS_POLICY_ID)
python python/policy/validate_rules.py inputs/rules.csv
python python/policy/create_rules.py   inputs/rules.csv
python python/policy/get_rules.py                     # read back what exists

# 4. Manual NAT (needs NAT_POLICY_ID; most version-sensitive script in the repo)
python python/nat/validate_nat.py      inputs/nat.csv
python python/nat/create_manual_nat.py inputs/nat.csv

# 5. Compliance report
python python/reports/compliance_report.py
```

**Ansible** — collection `cisco.fmcansible` (`>=1.0.0,<2.0.0`), needs `ansible-core`
2.21+ and therefore Python 3.12+:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
export FMC_HOST=https://fmc.example.local FMC_USERNAME=apiuser
read -rs FMC_PASSWORD && export FMC_PASSWORD

ansible-playbook -i ansible/inventory.yml ansible/playbooks/get_domain.yml
ansible-playbook -i ansible/inventory.yml ansible/playbooks/get_network_objects.yml
ansible-playbook -i ansible/inventory.yml ansible/playbooks/get_security_zones.yml
ansible-playbook -i ansible/inventory.yml ansible/playbooks/create_network_objects.yml
```

Objects created by `create_network_objects.yml` are defined in
`ansible/vars/network_objects.yml` — **edit that file, not the playbook**.
`ansible/group_vars/all.yml` holds no secrets; it reads `fmc_hostname`, `fmc_username`,
`fmc_password`, `fmc_verify_ssl`, and `domain_uuid` from the environment or an
`ansible-vault` file.

**Terraform** — provider `CiscoDevNet/fmc` `~> 2.5`, `required_version >= 1.6.0`.
Credentials are passed as `TF_VAR_*` so nothing lands on disk:

```bash
cd terraform
export TF_VAR_fmc_url=https://fmc.example.local TF_VAR_fmc_username=apiuser
read -rs TF_VAR_fmc_password && export TF_VAR_fmc_password

terraform init
terraform validate
terraform plan          # review every change before applying
```

Resource names and supported attributes depend on the provider version — confirm with
`terraform providers schema -json` before writing new resources. `main.tf` ships with its
example resource commented out on purpose; do not uncomment it as part of an unrelated
change. `terraform.tfstate` stores object values in cleartext and is gitignored.

**MCP servers** — each runs over `stdio` (default) or `http`:

```bash
cd mcp_servers/rest-api-mcp        # or ansible-mcp / terraform-mcp
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python client/test_client.py       # interactive smoke test
docker compose up -d --build       # or run it in a container
```

| Server | Package / entrypoint | HTTP port | Write flag (default `false`) | Compose service |
| --- | --- | --- | --- | --- |
| [rest-api-mcp](mcp_servers/rest-api-mcp/) | `python -m sfw_mcp_rest` | 8000 | `FMC_ALLOW_WRITES` | `sfw-mcp-rest` |
| [ansible-mcp](mcp_servers/ansible-mcp/) | `python -m sfw_mcp_ansible` | 8001 | `ANSIBLE_MCP_ALLOW_RUN` | `sfw-mcp-ansible` |
| [terraform-mcp](mcp_servers/terraform-mcp/) | `python -m sfw_mcp_terraform` | 8002 | `TF_MCP_ALLOW_APPLY` | `sfw-mcp-terraform` |

Register a server with an MCP client (Claude Desktop, VS Code, Cursor) using the block in
its README, for example:

```json
{
  "mcpServers": {
    "cisco-fmc-rest": {
      "command": ".venv/bin/python",
      "args": ["-m", "sfw_mcp_rest"],
      "cwd": "/absolute/path/to/mcp_servers/rest-api-mcp",
      "env": {
        "MCP_TRANSPORT": "stdio",
        "FMC_PROFILES_DIR": "profiles",
        "FMC_PROFILE_DEFAULT": "fmc-north-south",
        "FMC_ALLOW_WRITES": "false"
      }
    }
  }
}
```

Over HTTP the REST server answers on `http://127.0.0.1:8000/mcp`; the Ansible and
Terraform servers follow the same `/mcp` path on 8001 and 8002. Bind to `127.0.0.1`
unless the server sits behind a TLS-terminating, authenticating reverse proxy.

## Safety rules for agents

These are enforced in code, not just documentation. **Do not weaken them, and do not add
a tool or script that bypasses them.**

1. **Always run the matching `validate_*` script before any `create_*` script.** It is
   the only step that catches a malformed CSV before FMC sees it. Never suggest skipping
   it to "save a step".
2. **Read-only by default.** Every MCP write path stays disabled until its environment
   flag is explicitly set. New mutating functionality must be gated the same way.
3. **Preview before change.** Mutating MCP tools are split into a `preview_*` /
   `dry_run_*` / `plan_*` half that returns a plan plus a short-lived, content-bound
   confirmation token, and an `apply_*` / `run_*` half that refuses to run without that
   token. A model must never be able to mutate anything in a single call, or apply a plan
   different from the one a human reviewed. Preserve this split in any new tool.
4. **Allowlists, never free text.** The Ansible and Terraform servers execute a fixed
   `argv` list with `shell=False` against a resolved, allowlisted path
   (`ANSIBLE_PLAYBOOK_ALLOWLIST`, `TF_MCP_WORKSPACES`). Never introduce shell
   interpolation, a user-supplied binary, or user-supplied flags.
5. **TLS stays on.** Fix certificate errors with `FMC_CA_BUNDLE`, never by setting
   `VERIFY_SSL=false` / `fmc_insecure_skip_verify = true`.
6. **Redaction everywhere.** Credentials, tokens, and `Authorization` headers must be
   stripped from tool output and logs before they can reach a model context.
7. **Bounded blast radius.** Every subprocess keeps its timeout (`ANSIBLE_MCP_TIMEOUT`
   600s, `TF_MCP_TIMEOUT` 900s) and every response keeps its size cap.
8. **No deployment trigger.** These scripts change FMC configuration but never deploy it
   to devices. Do not add an automatic deploy step.
9. **Confirm the payload schema.** FMC payloads vary between releases. Before changing a
   write path, confirm the endpoint and fields in API Explorer on a real FMC
   (`https://<fmc-host>/api/api-explorer`) and say which version you verified against.

## Testing instructions

The full unit-test suite runs offline — **no FMC, no credentials, no network**. Run it
before and after every change:

```bash
pytest                                   # 193 tests at v1.0.0; all must pass
pytest --cov --cov-report=term-missing   # as CI runs it
```

`pyproject.toml` sets `testpaths = ["tests", "mcp_servers"]`, so a bare `pytest` from the
repository root also collects the per-server suites in
`mcp_servers/*/tests/`. Each server's `client/test_client.py` is an **interactive smoke
harness, not a pytest module** — it is excluded via `norecursedirs`; do not rename it or
add pytest test functions to it. Tests that need a reachable lab FMC must carry the
`@pytest.mark.integration` marker, which is deselected by default.

Run the same checks CI runs (`.github/workflows/ci.yml`) before opening a PR:

```bash
ruff check .                                    # lint
ruff format --check .                           # formatting
mypy python mcp_servers                         # types
bandit -c pyproject.toml -r python mcp_servers  # security
pip-audit -r python/requirements.txt --strict   # dependency CVEs
ansible-lint ansible/                           # needs Python 3.12+
terraform -chdir=terraform fmt -check
terraform -chdir=terraform init -backend=false && terraform -chdir=terraform validate
```

Pull requests additionally run `gitleaks`, CodeQL, and OSSF Scorecard, and start each MCP
server with `docker compose` to confirm it answers on `/mcp`. `pre-commit` mirrors most
of this locally (`ruff`, `ruff-format`, `bandit`, `gitleaks`, `terraform_fmt`,
`terraform_validate`, `detect-private-key`, and a local `no-env-files` hook).

- **MCP server links**

  - [mcp_servers/README.md](mcp_servers/README.md) — the shared safety model and
    transport selection
  - [mcp_servers/rest-api-mcp/](mcp_servers/rest-api-mcp/) — `list_fmc_profiles`,
    `get_inventory`, `search_objects`, `find_object_usage`, `list_access_rules`,
    `get_deployment_status`, `preview_object_changes`, `apply_object_changes`
  - [mcp_servers/ansible-mcp/](mcp_servers/ansible-mcp/) — `list_playbooks`,
    `describe_playbook`, `check_syntax`, `dry_run_playbook`, `run_playbook_for_real`
  - [mcp_servers/terraform-mcp/](mcp_servers/terraform-mcp/) — `list_workspaces`,
    `get_versions`, `init_workspace`, `validate_workspace`, `plan_workspace`,
    `explain_plan`, `detect_drift`, `show_state`, `apply_plan`
  - Reference implementation this project follows:
    [CiscoDevNet/CiscoFMC-MCP-server-community](https://github.com/CiscoDevNet/CiscoFMC-MCP-server-community)

- **Test the code with the Cisco DevNet sandbox**

  Visit https://devnetsandbox.cisco.com/DevNet to book a related sandbox — search the
  [sandbox catalogue](https://devnetsandbox.cisco.com/RM/Topology) for **Secure Firewall**
  or **Firepower**. Both always-on and reservable options exist. You need FMC 7.0+ with
  the REST API enabled.

  Sandbox FMCs normally present a self-signed certificate: download its CA and set
  `FMC_CA_BUNDLE` rather than setting `VERIFY_SSL=false`. Confirm connectivity with
  `python python/inventory/get_inventory.py` — if it writes files to `outputs/reports/`,
  credentials and connectivity are correct.

- **Latest Cisco API documentation**

  - https://developer.cisco.com/docs/ — Cisco developer documentation index
  - https://developer.cisco.com/secure-firewall/ — Secure Firewall developer centre
  - **API Explorer on your own FMC**: `https://<fmc-host>/api/api-explorer` — the
    authoritative schema for your release. **Always confirm write payloads here**, since
    fields differ between FMC versions.

- **SDK / IaC versions recommended for agents**

  - `cisco.fmcansible` Ansible collection `>=1.0.0,<2.0.0` —
    [CiscoDevNet/FMCAnsible](https://github.com/CiscoDevNet/FMCAnsible) (GPL-3.0)
  - Terraform provider `CiscoDevNet/fmc` `~> 2.5` —
    [CiscoDevNet/terraform-provider-fmc](https://github.com/CiscoDevNet/terraform-provider-fmc)
    (MPL-2.0)
  - [FastMCP](https://github.com/jlowin/fastmcp) for the MCP servers

- **Verification method**: after any live run, verify in three places — script output and
  the report in `outputs/reports/`, an API `GET` read-back, and the FMC GUI. For policy
  and NAT changes also check deployment state and functional behaviour on the FTD. Full
  method and rollback steps: [docs/TESTING.md](docs/TESTING.md).

## PR instructions

- **Security**: Do not commit real credentials or tokens. Use placeholders and document
  required env vars or files. Never commit a `.env`, an `ansible-vault` file, a CA
  bundle, a `terraform.tfstate`, or anything under `outputs/`. Sample data in `inputs/`
  and in tests must stay RFC 1918 / obviously fictional.
- **Licence headers are mandatory.** This repository is REUSE-compliant. Every new file
  needs the Cisco copyright and `SPDX-License-Identifier: Apache-2.0`, either inline or
  in a `.license` sidecar for formats that cannot carry comments (JSON, CSV, `.txt`).
  Copy the header style from a neighbouring file of the same type.
- **Tests are expected.** `CONTRIBUTING.md` asks for tests covering any affected
  behaviour. Add them under `tests/` for `python/`, or under the relevant
  `mcp_servers/*/tests/` for a server change.
- **Before committing**, run the full CI command list above and make sure `pytest`,
  `ruff`, `mypy`, and `bandit` are clean. Do not use `--no-verify` to skip pre-commit.
- **Scope**: keep a change to one area — `python/`, `ansible/`, `terraform/`, or a single
  MCP server. If you must cross-cut, explain why in the PR description.
- **Update the docs you invalidate.** A new script, env var, or MCP tool must also appear
  in `README.md`, the relevant server README, and this file.
- **State the FMC version** you validated a write path against, in the PR description and
  in any issue you open.

## Contribution conventions

- **Backward compatibility**: Do not change existing sample behavior unless clearly
  improving or fixing a bug; document changes. The project follows semantic versioning,
  so breaking changes may be held for the next major release. Record user-visible changes
  in `CHANGELOG.md`.
- **Coding style**: `ruff` is the single source of truth — `line-length = 100`, and the
  `F`, `E`, `W`, `I`, `UP`, `B`, `C4`, `SIM`, `PTH`, `S`, `RUF` rule sets. Prefer
  `pathlib` over `os.path` (`PTH`). Do not add per-line `# noqa` to silence a rule when
  the underlying issue is fixable, and do not widen the `ignore` list in
  `pyproject.toml` without justification.
- **Typing**: `mypy` runs with `check_untyped_defs` and `no_implicit_optional`. Annotate
  new public functions. Do not add blanket `# type: ignore`.
- **Clarity over cleverness.** This project is judged on clarity and safety as much as
  functionality, because the code talks to a firewall. Write for an engineer learning
  FMC automation: descriptive names, early returns, and no bare `except`.
- **Reports over prints.** Write per-row outcomes (`CREATED` / `SKIP` / `FAILED` plus a
  reason) to a CSV in `outputs/reports/` so a run can be attached to a change record.
  Existing objects are reported as `SKIP`, never overwritten, and a row referencing a
  missing object is `SKIP`, not a hard abort.
- **Dependencies**: pin with `~=` in the correct requirements file and keep each minimal.
  New dependencies must pass `pip-audit`.
- **Parity across the three styles.** A new capability ideally lands in Python, Ansible,
  and Terraform. If it only makes sense in one, say why in the PR.
- **Not a Cisco product.** This is community-maintained under
  [Apache-2.0](LICENSE) and is not supported by Cisco TAC. Do not add wording implying
  official Cisco support, and do not alter third-party licence records in
  [NOTICE](NOTICE).
