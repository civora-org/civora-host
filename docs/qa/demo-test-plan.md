# Civora demo — manual test plan

Click-through test plan for the local demo stack (`http://localhost:3000`).
Execute top to bottom; every case has numbered steps and an expected result (✅).
Record outcomes in the table at the end (Pass / Fail / Notes).

**Applies to:** civora-host `main` with `decidim-contracts_sk` **v1.3.0** (public UI redesign, header/footer overrides). Last updated 2026-10-03.

## 0. Before you start

1. Run the **built image**, not the engine-development override (the override runs `sleep infinity` with the engine mounted from a local checkout):
   ```bash
   docker compose -f compose.yaml up -d app
   ```
   ✅ `docker compose -f compose.yaml ps app` reports `healthy`; `http://localhost:3000/up` returns 200.
2. In a fresh browser profile, answer the cookie banner with **Accept only essential**.
3. Test data this plan creates uses the `MANUAL-2026-` reference prefix and is archived in §14. Never name test records `E2E…` or use demo-sounding titles: the demo DB doubles as the sales demo and the source of the civora.sk screenshots.

**Where things are**

| What | Value |
|---|---|
| Public URL | `http://localhost:3000` |
| Catalogue | `http://localhost:3000/contracts` |
| Admin catalogue | `http://localhost:3000/contracts/admin/contracts` |
| Audit trail | `http://localhost:3000/contracts/admin/audit_events` |
| Decidim admin | `http://localhost:3000/admin/` |
| Sign-in | `http://localhost:3000/users/sign_in` |
| User | `contracts-admin@example.org` |
| Password | in `tmp/demo-admin-credentials.txt` (gitignored, local only). **Never write the password into this file or any committed file.** The demo seed sets a random password; reset it locally if the file is missing. |

**Seeded demo records** (reference → state): DEMO-2026-001 → draft (§6 publishes it), DEMO-2026-002 → rejected, DEMO-2026-003 → returned, DEMO-2026-004 → published, DEMO-2026-005 → rejected, DEMO-2026-006 → archived, DEMO-2026-007 → archived, DEMO-2026-008 → published (CRZ mirror, stale by design), DEMO-2026-009 → published (CRZ mirror, stale by design), DEMO-OTHER-001 → other organization (invisible). Plus several thousand imported CRZ records.

> **Known leftovers from earlier runs:** `E2E Verify Zmluva` (E2E-2026-100), two `E2E …` documents on DEMO-2026-001 and amendment summaries `E2E prva verzia` on DEMO-2026-004 are test artefacts, not demo data. Clean them up before a sales demo or a screenshot session.

> If a step says "record the id", open the record and copy the numeric id from the URL.

---

## 1. Public site shell

**TC-101 — Homepage hero (en)**
1. Open `http://localhost:3000/?locale=en`.
✅ Hero shows "Public contracts of Slovak municipalities — transparent, structured, searchable." with a **Browse contracts** button linking to `/contracts`.

**TC-102 — Homepage hero (sk)**
1. Open `http://localhost:3000/?locale=sk`.
✅ Hero shows "Verejné zmluvy slovenských obcí a miest — …" with **Prezrieť zmluvy**.

**TC-103 — Header links**
1. Check the top-right icon row.
✅ Exactly **Pomoc** (question icon) and **Zmluvy** (document icon) — en: Help / Contracts — plus sign-in/account. No Meetings, no Activity.

**TC-104 — Topbar search routes to the catalogue**
1. Type `DEMO-2026-009` into the top search box, press Enter.
✅ Lands on `/contracts?q=DEMO-2026-009`; the catalogue's own search field is prefilled with the query; one register row: "Úprava kúpaliska — import z CRZ (zastarané)".

**TC-105 — Search no-results state**
1. Search for `xyzzy-undefined`.
✅ The localized no-matches message (sk: "Žiadna zmluva nezodpovedá vášmu hľadaniu." / en: "No contracts match your search.") between two hairlines; no broken layout.

**TC-106 — Footer**
1. Scroll to the footer (sk).
✅ Intro reads "Vitajte na platforme Civora." (with a space — not "naCivora") and "Verejné zmluvy, ich dokumenty a zmeny na jednom mieste. Prehľadne a dohľadateľne pre každého."
✅ First column: Domov + Zmluvy. Zdroje (Resources): **Otvorené dáta only**. No empty **Pomocník** column (it appears only when help topics are configured for the footer).

**TC-107 — Language switcher**
1. Use the language button (bottom bar) to switch sk ↔ en.
✅ Whole UI switches; catalogue and detail pages stay on the same record.

## 2. Public catalogue

**TC-201 — Page layout**
1. Open `/contracts` at a desktop width (≥ 1280 px).
✅ Clear space between the blue breadcrumb bar and the "Zmluvy" heading; the red bar under the heading does not touch the intro line ("Zverejnené zmluvy organizácie s dokumentmi a históriou zmien.").
✅ Search: label "Hľadať zmluvy" **above** the field; field and **Hľadať** button on one row, same height.

**TC-202 — Register rows list published records only**
1. Look at the list under the search.
✅ One hairline-separated row per contract: title link, `reference · date`, and the amount right-aligned (e.g. "148 500,00 EUR"). Rows with no amount show no amount and no dangling "EUR". Newest publications first. No draft/rejected/archived records anywhere.
✅ CRZ-mirrored rows (DEMO-2026-008/009) carry a grey "Externe potvrdené údaje · <date>" label; editorial rows carry none.

**TC-203 — Pagination**
1. Scroll to the pager.
✅ "Strana 1 z N" with Predchádzajúca/Ďalšia; page 2 does not repeat page 1's first row. With a search active, the `q` parameter survives the page links.

**TC-204 — Free-text search by title**
1. Search `kúpalisk`.
✅ At least one row with "kúpalisko/kúpaliska" in the title.

**TC-205 — Free-text search by reference is case-insensitive**
1. Search `demo-2026-004` (lowercase).
✅ The DEMO-2026-004 row renders.

## 3. Public contract detail

**TC-301 — Layout (editorial record, DEMO-2026-004)**
1. Open DEMO-2026-004 at desktop width.
✅ Title with its red bar clear of the line below; identity line "Číslo zmluvy: **DEMO-2026-004** · Dátum zverejnenia: …".
✅ Right-hand **Údaje o zmluve** panel (en: Contract details): amount as the large headline figure, then reference, dates and (if present) the CRZ link — each label directly above its own value, nothing drifting into a neighbouring row.
✅ Left column: "Predmet zmluvy" label with the subject as larger text, then Zmluvné strany, Dokumenty, História verzií, each with its red bar clear of the content below.

**TC-302 — Sparse fields are not rendered**
1. On a record with blank optional fields (e.g. no subject or no amount).
✅ Blank fields are absent — no empty rows, no dangling "EUR", no empty subject block.

**TC-303 — Editorial record has no provenance**
1. DEMO-2026-004 in sk and en.
✅ No "Externe potvrdené údaje" notice or label, no mirror date, no CRZ attribution.

**TC-304 — CRZ mirror provenance (DEMO-2026-009)**
1. Open DEMO-2026-009.
✅ A bordered notice with an info icon: "Externe potvrdené údaje", "Zrkadlené z registra CRZ dňa …", the **yellow warning label** "Toto zrkadlenie môže byť neaktuálne — overte pôvodný záznam na crz.gov.sk." and the attribution note (ekosystem.slovensko.digital, canonical record at crz.gov.sk).
✅ The facts panel shows the full CRZ URL as a link that wraps inside the panel.

**TC-305 — Parties**
1. Open a published record with parties (DEMO-2026-001 after §6).
✅ One row per party: name (bold) and address on the left; role label (Objednávateľ/Dodávateľ) and "IČO: …" on the right.

**TC-306 — Document download (public)**
1. On DEMO-2026-001's detail (published by §6), click an attached document.
✅ File downloads; the "(kind, size)" line under the title matches the file.

**TC-307 — Public version history**
1. Open DEMO-2026-004 (it has a published amendment).
✅ **História verzií**: "Aktuálna verzia" first, then "Verzia 1 · <date>" with the frozen snapshot fields, each label above its value. Draft amendments never appear.

**TC-308 — Invisible states are indistinguishable 404s**
1. From admin, note the ids of DEMO-2026-005 (rejected), DEMO-2026-006 (archived), DEMO-OTHER-001 (other org).
2. Visit each detail URL logged out (private window).
✅ All three **and** `/contracts/999999` render the same 404 page.

## 4. Admin access and index

**TC-401 — Unauthenticated redirect**
1. In a private window open `/contracts/admin/contracts`.
✅ Redirected to sign-in; after signing in you land back on the admin index.

**TC-402 — Sign-in failure**
1. Sign in with a wrong password.
✅ Localized error, no crash.

**TC-403 — Admin index**
1. Sign in; open `/contracts/admin/contracts`.
✅ All organization records with state chips; per-state counter chips at the top; search + state/source filters; pagination.

**TC-404 — Index filters**
1. Filter state = `published`; then source = `crz`; then search `DEMO`.
✅ Each filter narrows correctly; filters combine; counter chips ignore the active filter; "clear filters" appears when a filter yields zero rows.

**TC-405 — Audit-trail link**
1. Follow the audit-trail link from a contract's edit page.
✅ `/contracts/admin/audit_events?contract_id=<id>` renders that record's events only, with a "Zobraziť všetky udalosti" link back.

## 5. Contracts CRUD

**TC-501 — Create**
1. Admin index → new contract. Title: `Manuálny test zmluva`, reference: `MANUAL-2026-001`.
✅ Created in `draft`; edit page opens.

**TC-502 — Draft edit form**
✅ Title/reference/subject/amount/currency/date fields present. No field for state, organization or author. Amount shows a dot-decimal hint; currency is a **select** with EUR.

**TC-503 — Amount validation**
1. `12,50` → save. ✅ Rejected (comma decimals are deliberately rejected).
2. `1e5` → save. ✅ Rejected.
3. `12.50` → save. ✅ Accepted.
4. `125000000000` (over the decimal(12,2) ceiling) → save. ✅ Rejected.

**TC-504 — IČO validation**
1. Parties page → add a party with IČO `123`.
✅ Rejected (blank or exactly 8 digits). `12345678` → accepted.

**TC-505 — Reference uniqueness**
1. Create another contract with reference `MANUAL-2026-001`.
✅ Rejected — reference must be unique per organization.

## 6. Lifecycle transitions

**TC-601 — Submit**
1. On `MANUAL-2026-001` (draft) press **Submit**; confirm the dialog.
✅ State → `in_review`; success flash; audit row written (§10).

**TC-602 — Return requires a reason**
1. Press **Return** without a reason. ✅ Refused with a "reason required" alert; state unchanged.
2. Fill the reason ("Doplňte predmet zmluvy.") and confirm. ✅ State → `returned`; reason recorded.

**TC-603 — Reviewer decision banner**
1. Open the returned record's edit page.
✅ A "Reviewer decision" banner shows the reason and its date.

**TC-604 — Resubmit clears the banner**
1. Edit the record, then Submit again.
✅ State → `in_review`; banner gone.

**TC-605 — Approve / Reject with reason**
1. Approve → `approved`.
2. Create `MANUAL-2026-002`, submit, then Reject with a reason → `rejected` (terminal).

**TC-606 — Wrong-state refusal**
1. Try Approve on a fresh **draft** (via the row menu).
✅ Refused — approve is only valid from `in_review`.

**TC-607 — Double-submit refusal**
1. Repeat the same transition twice quickly.
✅ Second attempt refused (state already moved on).

**TC-608 — Publish DEMO-2026-001**
1. Take DEMO-2026-001 through submit → approve → redaction confirmation (§7) → publish. Skip if an earlier run already published it.
✅ It appears in the public catalogue (needed by TC-305/306).

## 7. Privacy-redaction gate (ADR-007)

**TC-701 — Publish without the stamp fails closed**
1. Take `MANUAL-2026-001` through submit → approve; press **Publish**.
✅ Refused with the redaction-gate flash pointing at the edit page. Record stays `approved`.

**TC-702 — Confirm without the checkbox is refused server-side**
1. Submit the redaction form with the checkbox unticked.
✅ Refused with a localized alert; nothing written.

**TC-703 — Confirm then publish**
1. Open the "Privacy redaction" card, tick the checklist, confirm. ✅ Card flips to the confirmation stamp line.
2. Press **Publish**. ✅ State → `published`; the record appears in the public catalogue.

**TC-704 — Stamp is one-way on a published record**
1. Re-POST the confirmation.
✅ Refused — already stamped/published.

## 8. Parties, documents, CRZ handoff

**TC-801 — Parties CRUD on an editable record**
1. On a draft/returned record open **Parties**; add an `object` and a `contractor` party, add a second `contractor`, edit one name, remove one.
✅ All succeed; multiple same-role parties are legal.

**TC-802 — Parties refused on a published record**
1. Open Parties on DEMO-2026-004.
✅ Read-only/refused — no add/edit/remove actions.

**TC-803 — Documents upload**
1. On an editable record attach a small **real** PDF (meaningful title + kind), replace it, remove it.
✅ Each operation succeeds; name/type/size update from the file.

**TC-804 — Upload safety**
1. Attach a `.exe` (renamed text file). ✅ Rejected by the content-type allowlist.
2. Attach a > 10 MB file. ✅ Rejected by the size cap.

**TC-805 — CRZ handoff PDF**
1. On an **editable** record press **Generate CRZ handoff**. ✅ A `crz_export` document appears.
2. **Download**. ✅ A real PDF, labelled as a handoff aid (not a legal publication), sk-localized.
3. On a **published** record: Download works; Generate is refused.

## 9. Amendments and versions

**TC-901 — Amendment create/publish**
1. On `MANUAL-2026-001` (published) open **Amendments**; create a draft (next version, a realistic summary such as "Predĺženie termínu plnenia"); publish it.
✅ Draft → published; the public detail's História verzií shows it newest first.

**TC-902 — Published amendments are immutable**
✅ Edit/destroy of the published amendment is refused.

**TC-903 — Amendment gate backstop (editorial records)**
1. On a published editorial record **without** the redaction stamp, try to publish a draft amendment.
✅ Refused. (CRZ-mirrored records are exempt — TC-1102.)

**TC-904 — Amendments on drafts refused**
✅ Not available on a draft record.

## 10. Audit trail

**TC-1001 — Table layout**
1. Open `/contracts/admin/audit_events`.
✅ Columns Akcia / Záznam / Používateľ / Dátum / Dôvod rozhodnutia. Record titles are **left-aligned** links. Dátum shows **date and time** (e.g. "29. 09. 2026 22:47"), newest first. An empty decision reason shows a muted "—".

**TC-1002 — Trail reflects the plan's actions**
✅ Rows for every transition performed (submit/return/approve/reject/publish/archive), the redaction confirmation and the amendment publication — each with actor and timestamp.

**TC-1003 — Contract filter**
1. Add `?contract_id=<id of MANUAL-2026-001>`.
✅ Only that record's events, with the "Zobrazujú sa udalosti auditnej stopy pre: …" banner.

**TC-1004 — Bad filter is a 404**
1. `?contract_id=999999`. ✅ 404.

## 11. CRZ import

**TC-1101 — Invalid import fails gracefully**
1. Admin index → CRZ import form → id `99999999999` → submit.
✅ Localized error flash; no crash; no record created.

**TC-1102 — CRZ mirrors are exempt from the gate**
1. On DEMO-2026-008 (CRZ mirror, unstamped) publish a draft amendment (if present).
✅ Allowed without the stamp — already-public upstream data (ADR-008).

## 12. Roles and permissions (informational)

Both demo users hold all engine roles (config-time resolver: organization admins ⇒ editor + reviewer), so role separation cannot be exercised on this demo; the automated suite covers it.

**TC-1201 — Decidim admin sidebar**
1. Open `/admin/`.
✅ A **Zmluvy** entry renders in the sidebar.

## 13. Responsive and cross-browser

**TC-1301 — Phone width (375 px)**
1. Open `/contracts` and DEMO-2026-009's detail.
✅ No horizontal scrolling. Catalogue: search field and button stack, rows show the amount under the title. Detail: the **Údaje o zmluve** panel comes first, then subject, notice, parties (role/IČO under the name), documents. Long titles and the CRZ URL wrap. Hamburger menu shows a Zmluvy entry.

**TC-1302 — Print**
1. Print preview of a detail page.
✅ No header, footer or cookie banner; facts and content in one column.

**TC-1303 — Firefox + Safari/WebKit spot-check**
✅ Sign-in, catalogue, detail, one transition each — no console errors.

## 14. Clean up

1. Archive every `MANUAL-2026-*` record this run published; leave rejected ones as they are.
2. Remove any documents you attached for testing.
✅ The public catalogue shows only demo and CRZ records — nothing named "test", "manual" or "E2E".

---

## Results

| TC | Result (Pass/Fail) | Notes |
|---|---|---|
| §1 Public site shell (TC-101…107) | | |
| §2 Public catalogue (TC-201…205) | | |
| §3 Public detail (TC-301…308) | | |
| §4 Admin access and index (TC-401…405) | | |
| §5 Contracts CRUD (TC-501…505) | | |
| §6 Lifecycle (TC-601…608) | | |
| §7 Redaction gate (TC-701…704) | | |
| §8 Parties, documents, CRZ handoff (TC-801…805) | | |
| §9 Amendments (TC-901…904) | | |
| §10 Audit trail (TC-1001…1004) | | |
| §11 CRZ import (TC-1101…1102) | | |
| §12 Roles (TC-1201) | | |
| §13 Responsive/print/browsers (TC-1301…1303) | | |
| §14 Clean up | | |

*When a case fails: note the URL, the step number and a screenshot. Bugs go to `civora-org/civora-platform` as issues.*
