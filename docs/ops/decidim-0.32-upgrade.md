# Upgrade to Decidim 0.32.1

Record of the host move from Decidim 0.31.7 (Rails 7.2, Ruby 3.3) to Decidim 0.32.1 (Rails 8.1, Ruby 3.4, libvips), tracked in civora-org/civora-platform#185 and #186. Read it before updating a stack that still runs 0.31.7, such as the local demo stack. The routine update procedure stays in [local-stack-update.md](local-stack-update.md); this page lists what is different this time.

Source: the [v0.32.0 release notes](https://github.com/decidim/decidim/releases/tag/v0.32.0) and the spike `docs/spikes/decidim-upgrade-path.md` in `civora-org/decidim-contracts_sk`.

## What changed in the host

| Area | Change |
|---|---|
| Gems | `decidim` and `decidim-dev` 0.32.1, Rails 8.1.4, Ruby 3.4.7, shakapacker 9.7, devise 5, puma 7. The engine moves to tag `v1.8.1` (0.31 and 0.32 support, plus the locale-URL fixes and deprecation sweep that matter under 0.32) |
| `Gemfile` | `faker ~> 3.2` (0.32 eager-loads seed classes that require it, even in production; without it the app does not boot), `minitest ~> 5.27` (Rails 8.1 resolves minitest 6, which moved `minitest/mock` out) and `selma < 0.5.3` (0.5.3 is source-only and needs Rust; 0.5.2 has precompiled gems) |
| Config | `config.load_defaults 8.1`; `config/shakapacker.yml` replaced from Decidim's 0.32 template (`javascript_transpiler`, no `dev_server.https`); `npm` `@decidim/*` 0.32.1 plus `shakapacker` |
| Image | `ruby:3.4.7-slim` (Debian 13): `libvips42t64` replaces ImageMagick, `libicu76`, and `zlib1g-dev` in the builder. CI installs `libvips42t64` instead of ImageMagick |
| Routing | The engine is mounted inside `scope "/:locale"`; `/contracts` and `/contracts/*rest` redirect permanently (301), query kept, `format: false` so `/contracts/export.csv` keeps its extension |
| View overrides | Header links and search re-based on 0.32.1; accountability override moved from `results/_project` to `results/_result`; budgets `projects/show` re-copied; footer and hero cell are unchanged upstream |
| Tests | Paths carry the locale (`/sk/...`); `private_space` became `access_mode` (`restricted`); header link assertions stop at the bar's own links |
| Audit | 15 advisories cleared (ten Rails 7.2 EOL, two devise, one shakapacker, two puma). New: GHSA-j7xr-4g94-r9h3 (graphql, only under the opt-in `Execution::Next`). Left: graphql x2, rack-proxy, rubyzip. Pruning of the rest is civora-org/civora-platform#188 |

## URL behaviour after the upgrade

- Every Decidim page and every engine page lives under a locale prefix: `/sk/contracts`, `/sk/contracts/12`, `/en/processes`.
- An old un-prefixed link answers `301` to the prefixed one. The locale is taken from the `locale` parameter, the signed-in user, the session, or the organisation's default locale. `curl` needs `-L` to follow it.
- Host-owned routes (`/up`, `/healthz`, `/two_factor/...`, `/manifest`) have no prefix. Decidim appends `?locale=sk` to links to them.
- Stored content with a raw path, such as the hero CTA setting `/contracts`, the omnipresent banner URL and the demo seed links, keeps working through the redirect. Edit it to the prefixed form if the extra hop matters.
- Health checks and uptime probes must hit `/up` or `/healthz`, not `/` or `/contracts`: those now redirect.
- Third parties that stored `/contracts/...` URLs (open data consumers, CRZ handoff, feed readers) are served by the 301. A client that does not follow redirects needs the new form.

## Breaking changes hit, and the fix

| Symptom | Cause | Fix |
|---|---|---|
| `bundle install` in Docker: `charlock_holmes` fails with "libz missing" | Debian 13 slim has no zlib headers | `zlib1g-dev` in the builder stage |
| Production boot: `cannot load such file -- faker` | decidim-comments `seed.rb` is eager-loaded and requires faker | `gem "faker"` in the default group |
| Docker: `Could not open library 'vips.so.42'` at `assets:precompile` | the app loads ruby-vips at boot, also in the builder | `libvips42t64` in the builder stage too |
| Docker: `selma` build needs `cargo` | selma 0.5.3 has no precompiled gem | `gem "selma", "< 0.5.3"` |
| `cannot load such file -- minitest/mock` | minitest 6 | `gem "minitest", "~> 5.27"` in the test group |
| Redirects instead of 200 for `/`, `/admin`, `/users/sign_in` in tests | locale in the URL | tests use `/sk/...` paths; two-factor tests compare redirect targets by path |
| `Translation missing: decidim.menu.help` | key removed upstream | the Help link now uses `layouts.decidim.footer.help` |
| Header "Meetings / Activity" block gone | upstream header has only the account block and the Menu dropdown | our Help, contracts and Participation links are inserted above the account block, marked `<%# Civora: start %>`; a drift test pins the rest to the gem |
| Accountability override ignored | the partial is now `results/_result` | override moved and re-copied |
| Restricted process still counted as visible | `private_space` is gone; `access_mode` replaces it | tests use `:restricted` |
| 89 rubocop offences | the 0.32 rubocop config enforces hash shorthand and `unprocessable_content` | `rubocop -a` (safe cops) plus two manual edits |
| `Rake::Task` test failed by random order | an earlier test had invoked the task | `task.reenable` before the first invoke |

## Database

`bin/rails decidim:upgrade` copies the new Decidim migrations and rewrites the old copied ones (52 files marked "modified by `decidim upgrade:migrations`"; that only matters for fresh installs). The new migrations are **destructive**:

- the `decidim_user_group_id` columns and the user group tables are dropped (user groups were deprecated in 0.31);
- the legacy image columns, participatory process types, assemblies types and the collaborative drafts tables are dropped;
- `private_space` becomes `access_mode`; `participatory_space_private_users` becomes `decidim_members`.

The Civora host uses none of these features, but the migration still deletes any rows there. **Take the backup first** (step 1 of the local stack update) and keep it until the stack has run a day.

## One-time tasks

Run on the upgraded stack, in this order:

```bash
bin/rails db:migrate
bin/rails data:migrate                                  # fills organisation short_name for the PWA manifest, renames
bin/rails decidim:upgrade:encryption                    # re-saves authorisations so metadata is encrypted with SHA256
bin/rails decidim:upgrade:remove_deleted_users_left_data
bin/rails decidim:upgrade:fix_deleted_members_follows
```

**Encryption.** `SECRET_KEY_BASE` does not change. Rails 8.1 and `load_defaults 8.1` derive keys with SHA256; Decidim's `AttributeEncryptor` still decrypts SHA1-era values through a legacy fallback, and `decidim:upgrade:encryption` only re-saves `Decidim::Authorization` rows to rewrite them. Keep `SECRET_KEY_BASE` and `tmp/local_secret.txt` backed up anyway; losing the key loses every encrypted value and signed link. On the throwaway database of this upgrade (no authorisations) all four tasks ran without output and without errors.

**Favicon.** `.ico` favicons are no longer supported (libvips). No favicon is tracked in the repo. If an organisation uploaded an `.ico` in the admin (the organisation's appearance settings), upload a PNG instead. Check with `Decidim::Organization.find_each { |o| puts [o.host, o.favicon.filename].inspect }`.

**Organisation short name.** Per the Decidim release notes, `data:migrate` derives `short_name` (PWA manifest) from the organisation name; one that ends up under three characters is left empty and must be set in the admin.

## Local dev stack (the demo stack)

Follow [local-stack-update.md](local-stack-update.md) with these changes:

1. Back up the database first and check the dump (step 1). The migrations above are not reversible without it.
2. Merge the upgrade PR, then `git pull --ff-only` in `~/Code/decidim-app`.
3. Point the engine worktree `host-main` at `v1.8.1`. Regenerate `Gemfile.dev-engine` from the new `Gemfile` (step 3).
4. `docker compose build app` takes longer this time: new base image (Debian 13), new gems, a full asset compile. Then `docker compose up -d app scheduler`.
5. In the container: `bundle install --local`, copy any new engine migrations verbatim (none are needed for `v1.8.1`; the host already has all 19), then `bin/rails db:migrate` and the one-time tasks above.
6. Start puma (step 8) and smoke-check with redirects followed:
   ```bash
   for u in http://localhost:3000/sk/ http://localhost:3000/sk/contracts http://localhost:3000/sk/processes http://vranov.localhost:3000/sk/contracts; do curl -sL -o /dev/null -w "%{http_code} $u\n" $u; done
   curl -sI http://localhost:3000/contracts | head -3   # 301 to /sk/contracts (or /en/ for an English default)
   ```
7. Check each organisation's default locale: the legacy redirect uses it, so an organisation with default locale `en` lands on `/en/contracts`.
8. Re-check the org favicon (see above) and click through the demo once.

`compose.dev.yml` still names the image `decidim/decidim:0.31.7`, which does not exist on Docker Hub (also before this upgrade); it is not touched here.

## Rolling back

Restore the database dump taken before the update, check out the previous host commit and engine commit, and rebuild (see *Rolling back* in [local-stack-update.md](local-stack-update.md)). The dump is the only way back: the schema migrations drop columns.

## Verification

Done on a separate Compose project (`civora-dec032`, port 3100, own volumes) and a throwaway PostgreSQL, never on the demo stack. Checked on the isolated stack with engine v1.8.1 and the fictional demo story (`civora:demo:proposal_to_contract`):

- `/up`, `/healthz` and `/sk/`, `/sk/contracts`, `/sk/contracts/1`, `/sk/contracts/suppliers/...`, `/sk/contracts/statistics`, `/sk/contracts/sitemap.xml`, `/sk/processes`, a result and a budget project page, `/sk/pages`, `/sk/pages/accessibility` and `/sk/users/sign_in` answer 200; `/sk/admin/` redirects to sign-in.
- `/contracts/1` and `/contracts/export.csv` answer 301 to `/en/contracts/1` and `/en/contracts/export.csv` (extension kept; the seeded organisation's default locale is `en`).
- The language chooser on a contract page switches `/sk/contracts/1` to `/en/contracts/1` without a 404; the page head carries `hreflang` alternates and an `og:url` without `?locale=`.
- The related-contracts block renders on the result page; libvips 8.16.1 loads; the production log has no errors or deprecation warnings.
- Not run: a live CRZ import and the CRZ handoff PDF (no network source configured on the isolated stack).
