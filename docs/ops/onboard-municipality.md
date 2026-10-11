# Onboarding a municipality

One scripted, idempotent path from "a new city" to "its catalogue is live"
(civora-org/civora-platform#140). The hosting model is ADR-011: one stack per
city; locally and in the demo several organizations may share one database,
which is why every step is keyed by the organization id.

What the tooling does, and what stays by hand:

| Step | Who |
| --- | --- |
| DNS record and TLS for the city's host name | you (once per city) |
| Organization, first admin, default pages and homepage blocks | `civora:onboard:organization` |
| `CRZ_ICO_ORG_<id>` in `.env` | you; the task prints the exact line |
| First CRZ sync incl. rate-limit resume | `civora:onboard:crz_sync` / `bin/crz-first-sync` |
| Verification (IČO scope, admin, defaults) | `civora:onboard:verify` |
| Logo, colours, homepage hero text, privacy and accessibility pages | by hand in `/system` and `/admin` (see 7) |

All commands run inside the app container in a stack
(`docker compose exec app …`) or directly in a development checkout
(prefix `DISABLE_SPRING=1`). Output carries ids and counts only; the admin
password is read from the environment and never printed.

## 1. DNS

Point the city's host name (for example `vranov.example.sk`) at the stack and
set it as `SITE_ADDRESS` in `.env` when the TLS overlay is used
(`compose.tls.yml`, `docs/ops/demo-server.md`). Locally, `*.localhost` names
resolve to 127.0.0.1 without any DNS.

The host name in the YAML (step 2) is what Decidim matches the request
against: a request for another name finds no organization.

## 2. Describe the city

Copy the example and fill it in. It holds no secrets.

```bash
mkdir -p tmp/onboarding
cp config/onboarding/example.yml tmp/onboarding/vranov.yml
$EDITOR tmp/onboarding/vranov.yml
```

Keys: `host`, `secondary_hosts`, `name` (per locale), `short_name` (3 to 12
characters), `default_locale` (`sk`), `available_locales` (`[sk, en]`),
`time_zone` (`Bratislava`), `reference_prefix`, `users_registration_mode`,
`ico` (8 digits; the Slovak IČO checksum is verified, so a typo is refused
before anything is written), `admin_email`, `admin_name`.

## 3. Create the organization and the first admin

Preview first; it writes nothing:

```bash
DRY_RUN=1 bin/rails "civora:onboard:organization[tmp/onboarding/vranov.yml]"
```

Then run it. Pass the admin password only through the environment of this
one command (use a generated value, not shell history of a real password):

```bash
ONBOARD_ADMIN_PASSWORD="$(openssl rand -base64 18)" \
  bin/rails "civora:onboard:organization[tmp/onboarding/vranov.yml]"
```

Without `ONBOARD_ADMIN_PASSWORD` the admin gets Decidim's invitation e-mail
(SMTP must work) and sets the password there. With it, the admin is
confirmed, has accepted the admin terms and can sign in at once; the password
is applied only to an admin who has none yet, never overwritten on a re-run.

How it works: a new organization is created through Decidim's own system
command (`Decidim::System::CreateOrganization`), so default pages, help pages
and homepage content blocks exist as if created in `/system`. Settings the
command does not take (names in all locales, time zone) are then converged.
Running it again with the same file changes nothing; changed values in the
file are applied to the existing organization.

The task ends by printing the organization id and the line for step 4.

## 4. Set the IČO scope

Add the printed line to the stack's `.env` (it is the only thing that tells
the engine which contracts belong to this city; an organization without it is
refused by the sync, never imported unscoped):

```
CRZ_ICO_ORG_<organization id>=<ico>
```

Recreate the containers that read it (`docker compose up -d app scheduler`);
a running process does not see a changed `.env`. Several organizations on one
database each get their own line.

## 5. First CRZ sync

```bash
bin/crz-first-sync <organization id> 2026-01-01T00:00:00Z
# same thing:
bin/rails "civora:onboard:crz_sync[<organization id>,2026-01-01T00:00:00Z]"
```

`SINCE` defaults to 30 days ago (`ONBOARD_SINCE` overrides). A long window
runs into the ekosystem datahub limit of 60 requests a minute: the engine
stops with `sync stopped early: ... gave up on <url with since=...>` (HTTP
429). The task parses that `since=`, waits 65 seconds for the rate window and
runs the sync again from there, until a pass ends without "stopped early".
It is bounded: 40 passes at most, and it gives up after 3 passes in a row
that made no progress, with a non-zero exit. Any other failure (for example
`No import actor`) stops at once. A re-run is safe; the sync is idempotent.

Needs an admin with accepted admin terms in the organization (step 3), or
`ACTOR_EMAIL` pointing at one. After this, the nightly scheduler
(`docs/ops/crz-sync.md`) keeps the organization current.

## 6. Verify

```bash
bin/rails "civora:onboard:verify[<organization id>]"
```

Prints `ok` / `FAIL` per check and exits 1 on any failure:

- the IČO is set in this process and passes the checksum;
- no other organization uses the same IČO;
- default locale `sk`, time zone `Bratislava`;
- an admin with a password and accepted admin terms exists;
- the IČO isolation check: zero mirrored contracts with the IČO on neither
  party (the engine's `prune_out_of_scope` dry run);
- the contract and published counts.

By hand, in a browser at the city's host:

1. `/contracts` lists only this city's contracts (open a few; the city is a
   party). With a second organization on the same database, its host shows
   its own, different list, and the two share no contract.
2. The page is Slovak by default; the language switcher offers English.
3. Sign in as the new admin at `/admin`; `/contracts/admin` opens.
4. If anything foreign was ever imported (an organization synced before the
   IČO was set): back up, then
   `bin/rails "decidim_contracts_sk:crz_import:prune_out_of_scope[<id>]"`
   (dry run) and again with `CONFIRM=1`.
5. Walk `docs/qa/demo-test-plan.md` sections 0 to 3 for the acceptance.

## 7. By hand: look and legal pages

Not scripted, because they are content decisions of the city:

- `/system`: logo, colours.
- `/admin` → Pages: terms of service, privacy notice, accessibility
  statement. The homepage hero (welcome text, link to `/contracts`) is the `hero`
  homepage content block in the Decidim admin (the seed sets a default).

## Re-running and undoing

Every command above can be re-run. There is no automated teardown; removing a
city is a database operation outside this runbook. Pushgateway keeps metrics
of removed organizations (see `docs/ops/crz-sync.md`, Alerting).
