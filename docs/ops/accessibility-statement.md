# Accessibility statement

Tracked in [`civora-org/civora-platform#133`](https://github.com/civora-org/civora-platform/issues/133). A public-sector website needs a "vyhlásenie o prístupnosti" (EU Directive 2016/2102, model statement in Implementing Decision (EU) 2018/1523). The host publishes it as a Decidim static page, Slovak and English, linked in the footer.

## Publish or update

```bash
ACCESSIBILITY_CONTACT_EMAIL=access@example.org \
  bin/rails "civora:accessibility_statement:publish[<organization_id>]"
```

- Without an id, every organization gets its own page; with one, only that organization.
- The page is the static page with slug `accessibility`, public at `/pages/accessibility`. It is found by (organization, slug) and rewritten, so running the task again updates the page and never duplicates it.
- Docker: `docker compose exec app bin/rails "civora:accessibility_statement:publish"`.
- Contact address, in order: `ACCESSIBILITY_CONTACT_EMAIL`, then the organization's sender address (Decidim admin, Settings, Appearance/SMTP `from_email`), then a visible placeholder `[doplniť kontaktný e-mail]` in the text. Never leave the placeholder in a pilot: set the variable before the pilot opens.
- The footer link ("Vyhlásenie o prístupnosti" / "Accessibility statement", Resources column) appears only when the page exists, so it never points at a 404 (`app/views/layouts/decidim/footer/_main_links.html.erb`).

The text lives in `app/lib/accessibility_statement.rb`. Edits made to the page in the Decidim admin are overwritten by the next run: change the text in code, not in the admin.

## Before it goes live: open items

1. The two `[overiť s právnikom]` marks (legal basis: zákon č. 95/2019 Z. z. and its implementing decree; the supervisory body to name) must be confirmed with a lawyer and replaced by the exact references.
2. The manual keyboard-only and screen-reader pass (NVDA on Windows, VoiceOver on macOS/iOS) is not done. The statement says so. After the pass, move the result into the "Neprístupný obsah" list, update `PREPARED_ON` and `DATE_TEXT`, and re-run the task.
3. The contact address must be a monitored mailbox.

## Audit behind the statement (2026-10-11)

axe-core 4.x through Playwright against the local host (engine v1.7.1 plus the fixes in `civora-org/decidim-contracts_sk#141`; before them the admin also showed a 1.7:1 contrast failure and an unfocusable scroll region), WCAG 2.0/2.1 A and AA rules, serious or critical findings:

| Page | 1440 px | 375 px |
|------|---------|--------|
| Catalogue `/contracts` | 0 | 0 |
| Contract detail | 0 | 0 |
| Statistics | 0 | 0 |
| Statement page `/pages/accessibility` | 0 | 0 |
| Admin (overview, list, new/edit, parties, audit trail) | 1 critical + 1 serious | 1 critical + 2 serious |

All admin findings left after the engine fixes sit in Decidim's own admin navigation (ARIA roles, list children, unnamed menu button); the statement lists them as known non-conformities. Targets smaller than 24 px (WCAG 2.2, criterion 2.5.8) are reported separately in the statement. Re-audit after every Decidim upgrade and engine release, then update `app/lib/accessibility_statement.rb`.

Test-only caveat: the statement describes automated checks only. It claims no screen-reader result.
