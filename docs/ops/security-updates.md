# Security updates

How the Civora host app is kept patched (civora-org/civora-platform#136): what is checked automatically, the cadence of manual work, how an emergency patch is made, and how the upstream-blocked advisories in `.bundler-audit.yml` are reviewed. When a vulnerability is already being exploited on a stack, switch to [incident-response.md](incident-response.md).

Roles: the **maintainer** does all of this in the pilot (see the roles table in the incident-response document).

## What is pinned today

| Component | Pin | Where |
|---|---|---|
| Decidim | 0.32.1 (exact, `=`) | `Gemfile`, `Gemfile.lock` |
| `decidim-contracts_sk` engine | tag `v1.8.0` (git source) | `Gemfile`, `Gemfile.lock`; upgrade steps in README *Upgrading the engine* |
| Rails | 8.1.4 (supported until 2027-10-10; forced by Decidim) | `Gemfile.lock` |
| Ruby | 3.4.7 | `.ruby-version`, `Dockerfile` (`ruby:3.4.7-slim`), CI |
| PostgreSQL | 17 | `compose.yaml`; CI service is aligned |
| Node | 22.14.0 | `.node-version` |

Decidim's meta-gems pin each other and Rails to narrow ranges, so the host cannot move individual core gems freely: `decidim-core` pins `rails ~> 8.1.0`, `shakapacker ~> 9.7.0`, `rubyzip ~> 2.0` and `rack-proxy ~> 0.8.3, < 1.0`, `decidim-api` pins `graphql >= 2.4.17, < 2.6` (all in `Gemfile.lock`). That is why part of the advisory list cannot be fixed here.

## What runs automatically

| Control | Trigger | What it does | Where |
|---|---|---|---|
| `bundler-audit check --update` | every PR and every push to `main` | Fails the build on any advisory not listed in `.bundler-audit.yml` | `.github/workflows/ci.yml`, job `audit` |
| Brakeman `--exit-on-warn` | every PR and push to `main` | Fails on any new warning; the Rails 7.2 EOL ignore in `config/brakeman.ignore` is obsolete since the 0.32.1 upgrade and is removed in civora-org/civora-platform#188 | `ci.yml` job `brakeman`, `config/brakeman.ignore` |
| gitleaks, full history | every PR and push to `main` | Fails on committed secrets | `ci.yml` job `secret-scan`, `.gitleaks.toml` |
| RuboCop, minitest | every PR and push to `main` | Lint and tests (Postgres 17) | `ci.yml` jobs `lint`, `test` |
| Dependabot | weekly | Opens PRs for GitHub Actions and the Docker base image only | `.github/dependabot.yml` |

Two limits to keep in mind:

- **CI only runs on code changes.** The workflow has no `schedule:` trigger, so a new advisory against an unchanged `main` is not noticed until the next PR or push. The weekly check below covers that gap.
- **Dependabot does not cover Ruby gems.** The bundler ecosystem is deliberately off (the private git-pinned engine cannot be resolved), so gem updates are reviewed `bundle update` PRs made by hand, per the note in `.github/dependabot.yml`.

The CI/CD plan in the platform repository (`docs/05-operations/civora-ci-cd-plan.md`) sets the quality gate this policy follows: no critical vulnerability unpatched for more than 7 days.

## Cadence

| When | What | Who |
|---|---|---|
| **Weekly** (fixed day) | `bundle exec bundler-audit check --update` against `main`; review the Dependabot PRs (merge when CI is green); look at open advisories for Decidim and the engine | Maintainer |
| **Monthly** | `bundle outdated --strict`; a conservative `bundle update` PR (`bundle update --conservative`), reviewed lock diff, CI green; review every entry in `.bundler-audit.yml` ([below](#upstream-blocked-advisories)) | Maintainer |
| **On each Decidim patch release** | Bump `decidim` and the `decidim-dev` pin together, re-run the audit, remove every ignore that no longer applies, rebuild, walk the demo test plan ([`docs/qa/demo-test-plan.md`](../qa/demo-test-plan.md)) | Maintainer |
| **On each engine release** | Follow README *Upgrading the engine* | Maintainer |
| **Quarterly** | Check Ruby, Node, base-image and Postgres support status; rebuild the image from scratch so base-image security fixes land | Maintainer |
| **At pilot start and end** | Full audit, all ignores re-justified in writing | Maintainer |

Every update goes through a PR with CI green and is deployed with `scripts/deploy.sh` (backup-gated, migrates, smoke test, `/healthz`). Do not patch a running container in place.

### Severity and time to patch

| Severity | Target (from the day the fix is available and resolvable) |
|---|---|
| Critical, or actively exploited | Emergency path, [below](#emergency-patch) |
| High | 7 days |
| Medium | Next monthly update |
| Low | Next Decidim release |

Severity is the advisory's own rating, adjusted by exposure: whether the vulnerable code path is reachable in this stack. Write the adjustment down in the PR.

## Emergency patch

For a critical or actively exploited advisory against a gem or the image that this stack can resolve:

1. Branch from `main`; make the smallest change: `bundle update --conservative <gem>` (or the base-image bump).
2. Confirm the fix with `bundle exec bundler-audit check --update`, then the full CI run. Do not skip jobs.
3. Deploy with `scripts/deploy.sh` the same day. If a stack is under attack, containment ([incident-response.md](incident-response.md)) comes before the patch.
4. Tell each municipality contact when the advisory was relevant to personal data or availability; if data may have been accessed, follow the breach procedure.
5. If the fix is not resolvable (a Decidim pin blocks it), there is no patch to deploy: apply a mitigation (disable or firewall the vulnerable surface, block the request pattern at the reverse proxy), record it next to the ignore entry, and put the entry on the weekly list until it is resolvable.
6. Write a short record: advisory, affected version, exposure, action, date.

## Upstream-blocked advisories

`.bundler-audit.yml` lists ignores **per advisory, never per gem**, so any new advisory still fails CI and forces a fresh decision. Each entry is blocked by a Decidim 0.32.1 pin. The 0.32.1 upgrade (civora-org/civora-platform#185) cleared the fifteen advisories that the 0.31.7 pins blocked: ten Rails 7.2 EOL CVEs, two devise, one shakapacker and two puma.

| Gem (locked version) | Why it cannot move | Fix needs | Advisories in `.bundler-audit.yml` |
|---|---|---|---|
| graphql 2.5.26 | `decidim-api` pins `< 2.6` | graphql >= 2.6.9 | GHSA-rmxg-5p3r-j6hh (parser-cache Marshal deserialization); GHSA-j7xr-4g94-r9h3 (authorization bypass, only under the opt-in `Execution::Next` runtime, which `decidim-api` never enables; needs >= 2.6.6) |
| rack-proxy 0.8.3 | `decidim-core` pins `< 1.0` | rack-proxy >= 1.0.3 | GHSA-42qh-8mx8-7wqm |
| rubyzip 2.3.2 | `decidim-core` pins `~> 2.0` | rubyzip >= 3.4.0 | CVE-2026-85396 (path traversal on extraction, High) |

The engine keeps the same list in its own `.bundler-audit.yml` ([engine repository](https://github.com/civora-org/decidim-contracts_sk/blob/v1.6.0/.bundler-audit.yml)); the host file mirrors it. Change both together.

### Review procedure

At the monthly review, and every time a Decidim release comes out:

1. For each row: does a resolvable fixed version exist now? Try `bundle update --conservative <gem>` on a throwaway branch and look at what Bundler says is holding it. Check whether the Decidim release notes relax the pin.
2. If the pin is gone, update the gem, delete the ignore **in the same PR**, and let CI prove the audit is clean.
3. If it is still blocked, keep the entry and re-confirm the **exposure** in one or two sentences next to it in the PR description: is the code path reachable on this stack (public, admin-only, build-time only, not enabled)? This exposure statement has not been written yet for the existing entries; the first review writes it, which also matters for the data-protection risk assessment each municipality may ask for.
4. Re-read `config/brakeman.ignore` on the same schedule (its Rails EOL entry is obsolete and goes in civora-org/civora-platform#188).
5. Update the header of `.bundler-audit.yml` and this table in the same PR when the list changes. Never add a gem-wide ignore, and never add an entry without naming what blocks it and what would unblock it.

### Exit plan

The stack is on a maintained Rails line (8.1) since the 0.32.1 upgrade. The remaining entries wait for a Decidim release that relaxes the graphql, rack-proxy and rubyzip pins; forking Decidim is ruled out. Until then keep the exposed surface small, re-confirm the exposure of the three entries at each review, and tell municipalities plainly (the DPA technical measures should not promise "all dependencies current"). Decidim supports only the last two minors, so plan the next upgrade (0.33) when it gets a date. Before each pilot extension, the maintainer decides again whether the residual risk is acceptable and records it.

## Related documents

- [incident-response.md](incident-response.md): what to do when a vulnerability has been exploited
- [secrets.md](secrets.md): token and key rotation (including `ENGINE_READ_TOKEN`)
- [environments.md](environments.md): parity between CI and production, staging-on-paper
- [restore-runbook.md](restore-runbook.md): the backup gate that `scripts/deploy.sh` enforces
- README *Upgrading the engine* and *CI*
