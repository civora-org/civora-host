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

`bin/rails decidim:upgrade` copies the new Decidim migrations and rewrites the old copied ones (52 files marked "modified by `decidim upgrade:migrations`"; that only matters for fresh installs). The new migrations are **destructive** and cannot be reversed without the backup.

### Pre-flight: count what 0.32 drops

Run this on the old database before anything else and keep the output next to the backup. Every non-zero count is data the upgrade deletes or rewrites. The Civora host is expected to show zeros except for the access-mode columns.

```sql
-- user groups (migrations 20261012200035 .. 20261012200055): memberships table and every decidim_user_group_id column
SELECT count(*) AS user_group_memberships FROM decidim_user_group_memberships;
SELECT count(*) AS group_users FROM decidim_users WHERE extended_data @> '{"group":true}';
SELECT table_name,
       (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM %I WHERE decidim_user_group_id IS NOT NULL', table_name), false, true, '')))[1]::text::int AS rows_with_group
  FROM information_schema.columns WHERE column_name = 'decidim_user_group_id' AND table_schema = 'public';
-- 20261012200039 deletes members without a user and duplicate (user, space) members before adding a unique index
SELECT count(*) AS members_without_user FROM decidim_participatory_space_private_users WHERE decidim_user_id IS NULL;
SELECT count(*) AS duplicate_members FROM (SELECT 1 FROM decidim_participatory_space_private_users GROUP BY decidim_user_id, privatable_to_type, privatable_to_id HAVING count(*) > 1) d;
-- dropped tables and columns
SELECT count(*) AS process_types FROM decidim_participatory_process_types;
SELECT count(*) AS assembly_types FROM decidim_assemblies_types;
SELECT count(*) AS collaborative_drafts FROM decidim_proposals_collaborative_drafts;
SELECT count(*) AS steps_with_cta FROM decidim_participatory_process_steps WHERE cta_path IS NOT NULL AND cta_path <> '';
-- legacy CarrierWave file columns (the ActiveStorage copies are kept; a value here with no attachment is lost)
SELECT (SELECT count(*) FROM decidim_organizations WHERE logo IS NOT NULL OR favicon IS NOT NULL OR official_img_footer IS NOT NULL) AS orgs_legacy_images,
       (SELECT count(*) FROM decidim_users WHERE avatar IS NOT NULL) AS users_legacy_avatar,
       (SELECT count(*) FROM decidim_participatory_processes WHERE hero_image IS NOT NULL) AS processes_legacy_hero,
       (SELECT count(*) FROM decidim_assemblies WHERE hero_image IS NOT NULL OR banner_image IS NOT NULL) AS assemblies_legacy_images;
```

(The members table name is the pre-0.32 one; the table is renamed to `decidim_members` by the same upgrade.) If the table or column of a query does not exist on your version, that part is already clean.

**User groups.** If `user_group_memberships` or `group_users` is non-zero, run `bin/rails decidim:upgrade:user_groups:remove` **before** `db:migrate`. It converts groups to ordinary users, transfers authorships and notifies the members. With zeros it is unnecessary.

### Access mode: the one that leaks if you forget

The schema migrations add `access_mode` with default `0` (open). Only Decidim's **data** migrations (`20260111190000` processes, `20260111185230` assemblies) copy the old `private_space` / `is_transparent` flags into it. Between `db:migrate` and `data:migrate` every private space is public. So:

- The image entrypoint now runs `db:prepare data:migrate db:seed` before puma starts, so a normal container start cannot serve the gap.
- When you migrate by hand, **stop the app first**, run `db:migrate` and `data:migrate` back to back, and only then start it.

Check before and after (the `access_mode` column exists only after the migration; before it, compare the flags alone):

```sql
-- before db:migrate
SELECT private_space, count(*) FROM decidim_participatory_processes GROUP BY 1;
SELECT private_space, is_transparent, count(*) FROM decidim_assemblies GROUP BY 1, 2;
-- after db:migrate AND data:migrate: 0 = open, 1 = transparent, 2 = restricted (see the enum in Decidim::ParticipatoryProcess)
SELECT private_space, access_mode, count(*) FROM decidim_participatory_processes GROUP BY 1, 2;
SELECT private_space, is_transparent, access_mode, count(*) FROM decidim_assemblies GROUP BY 1, 2, 3;
```

Every row with `private_space = true` must show a non-zero `access_mode`. Any `true / 0` row means the data migration did not run: stop the app and run `bin/rails data:migrate`.

## One-time tasks

Run on the upgraded stack **with the app stopped**, in this order:

```bash
bin/rails db:migrate
bin/rails data:migrate                                  # access_mode backfill (above), organisation short_name for the PWA manifest, renames
bin/rails decidim:upgrade:encryption                    # re-saves authorisations AND the host's two-factor seeds with the SHA256 key
bin/rails decidim:upgrade:remove_deleted_users_left_data
bin/rails decidim:upgrade:fix_deleted_members_follows
```

Then start the app.

**Encryption.** `SECRET_KEY_BASE` does not change. Rails 8.1 and `load_defaults 8.1` derive keys with SHA256; Decidim's `AttributeEncryptor` still decrypts SHA1-era (0.31) values through a legacy fallback, and `decidim:upgrade:encryption` re-saves `Decidim::Authorization` rows to rewrite them. Decidim's task knows nothing about host tables, so the host adds `civora:upgrade:encryption` (`app/lib/two_factor/reencryption.rb`), which re-saves every TOTP seed and is hooked in as a prerequisite of the Decidim task. It can also be run alone and is idempotent. `test/lib/legacy_sha1_encryption_test.rb` pins both halves with real Rails 7.2 ciphertexts: a 0.31 seed still decrypts, the restore drill accepts it, and after the task it decrypts without the SHA1 fallback. Keep `SECRET_KEY_BASE` and `tmp/local_secret.txt` backed up; losing the key loses every encrypted value and signed link. See also [decidim-032-secrets-runbook.md](decidim-032-secrets-runbook.md) and run `scripts/restore_drill.sh` against a fresh backup before relying on it.

**Favicon.** `.ico` favicons are no longer supported (libvips). No favicon is tracked in the repo. If an organisation uploaded an `.ico`, upload a PNG instead. Check (organisations without a favicon are skipped) with:

```ruby
Decidim::Organization.find_each { |o| puts [o.host, o.favicon.filename.to_s].inspect if o.favicon.attached? }
```

**Organisation short name.** Per the Decidim release notes, `data:migrate` derives `short_name` (PWA manifest) from the organisation name; one that ends up under three characters is left empty and must be set in the admin.

## Local dev stack (the demo stack)

Follow [local-stack-update.md](local-stack-update.md); the app container there starts puma itself (image `civora-host:dev`), which changes the order around the database work:

1. Back up the database first and check the dump (step 1). Run the pre-flight SQL above and save its output.
2. Merge the upgrade PR, then `git pull --ff-only` in `~/Code/decidim-app`.
3. Point the engine worktree `host-main` at `v1.8.1`. Regenerate `Gemfile.dev-engine` from the new `Gemfile` (step 3).
4. Build the production image, then the dev image on top of it (step 5). The first build is slower: new base image (Debian 13), new gems, a full asset compile. **Do not start the new app yet**: the override starts puma on container start, and the old schema must not be served by new code (and the new schema not before `data:migrate`). Either leave the old container stopped (`docker compose stop app scheduler`) or run the migration in a one-off container: `docker compose run --rm --no-deps app sh -c 'bundle install --local --quiet && bin/rails db:migrate data:migrate decidim:upgrade:encryption decidim:upgrade:remove_deleted_users_left_data decidim:upgrade:fix_deleted_members_follows'` (the engine migrations: none needed for `v1.8.1`, the host already has all 19).
5. Start the app: `docker compose up -d app scheduler`. Puma starts by itself.
6. Smoke-check with redirects followed:
   ```bash
   for u in http://localhost:3000/sk/ http://localhost:3000/sk/contracts http://localhost:3000/sk/processes http://vranov.localhost:3000/sk/contracts; do curl -sL -o /dev/null -w "%{http_code} $u\n" $u; done
   curl -sI http://localhost:3000/contracts | head -3   # 301 to /<organisation default locale>/contracts
   ```
7. Re-run the access-mode SQL (above) and the favicon check, then click through the demo once.

Legacy links: `/contracts/...` GETs answer 301 to `/<locale>/contracts/...` (the locale is the `locale` parameter, the signed-in user's, the session's, else the **organisation's default**), POSTs from old pages and e-mails (the one-click unsubscribe) are served in place. Decidim's own legacy redirects (`/search`, `/pages`, ...) use a different detector that falls back to the application default locale (`en`) before the organisation's; that is upstream behaviour and not changed here.

`compose.dev.yml` still names the image `decidim/decidim:0.31.7`, which does not exist on Docker Hub (also before this upgrade); it is not touched here.

## Rolling back

Restore the database dump taken before the update, check out the previous host commit and engine commit, and rebuild (see *Rolling back* in [local-stack-update.md](local-stack-update.md)). The dump is the only way back: the schema migrations drop columns.

## Verification

Done on a separate Compose project (`civora-dec032`, port 3100, own volumes) and a throwaway PostgreSQL, never on the demo stack. Checked on the isolated stack with engine v1.8.1 and the fictional demo story (`civora:demo:proposal_to_contract`):

- `/up`, `/healthz` and `/sk/`, `/sk/contracts`, `/sk/contracts/1`, `/sk/contracts/suppliers/...`, `/sk/contracts/statistics`, `/sk/contracts/sitemap.xml`, `/sk/processes`, a result and a budget project page, `/sk/pages`, `/sk/pages/accessibility` and `/sk/users/sign_in` answer 200; `/sk/admin/` redirects to sign-in.
- `/contracts/1` and `/contracts/export.csv` answer 301 to `/en/contracts/1` and `/en/contracts/export.csv` (extension kept; the seeded organisation's default locale was `en`; since the review fix the redirect uses the organisation's default locale explicitly).
- The language chooser on a contract page switches `/sk/contracts/1` to `/en/contracts/1` without a 404; the page head carries `hreflang` alternates and an `og:url` without `?locale=`.
- The related-contracts block renders on the result page; libvips 8.16.1 loads; the production log has no errors or deprecation warnings.
- Not run: a live CRZ import and the CRZ handoff PDF (no network source configured on the isolated stack).

Review round (PR #43), checked live on the isolated stack with the rebuilt image:

- **Access mode at boot.** A process was set to `private_space = true, access_mode = 0` and the two data-migration rows were deleted; restarting the container ran `db:prepare data:migrate db:seed` through the entrypoint, logged both "Backfilling ..." steps and left `access_mode = 2` (restricted); an anonymous request for it answered 302 (sign-in).
- **Restore drill with 0.31 ciphertext.** A TOTP seed and an authorization value were written with a real Rails 7.2.3.2 / decidim-core 0.31.7 SHA1 ciphertext under the stack's `SECRET_KEY_BASE`, a backup in the `scripts/backup.sh` layout was taken from the throwaway stack, and `scripts/restore_drill.sh` restored it into a separate drill project (`DRILL_IMAGE=civora-host:dec032-test`, port 3101): `encryption check OK: decrypted two_factor_credentials=1 authorizations=1`, HTTP 200 (through `/contracts` with `-L`), counts equal to the manifest, **PASS**. The log line was not kept: it belongs to a throwaway stack.
