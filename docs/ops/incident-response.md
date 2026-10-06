# Incident response

What to do when something goes wrong on a Civora host stack (civora-org/civora-platform#136): who is told, how fast, how a personal-data breach is reported, and how the evidence is kept. Companion to [security-updates.md](security-updates.md) (how vulnerabilities are patched before they become incidents).

Roles are named by function, never by person. In the pilot the **maintainer** is one person who also receives the alerts; the **municipality contact** is the person the municipality names in its processing agreement. Contact details live in the signed agreement and the stack's private operations notes, **not in this repository**. Wherever this document shows `[...]`, fill it in from there.

## Roles

| Role | Who | In an incident |
|---|---|---|
| **Maintainer** | Operates the stack (deploys, backups, alerts, patches) | Detects or receives the report, triages, contains, recovers, writes the record, informs the municipality contact |
| **Municipality contact** | The controller's named contact (the municipality is the *prevádzkovateľ*, Civora the *sprostredkovateľ*) | Receives the notification, decides on and files the report to the supervisory authority and on informing data subjects |
| **Municipality data-protection officer** (*zodpovedná osoba*) | The controller's own DPO, where the municipality has one | Advises the controller; the maintainer gives them the facts they ask for |
| **Backup maintainer** | A second person named in the private operations notes, **if one exists** | Covers when the maintainer is unreachable. The pilot has no second person yet, see [Known gaps](#known-gaps) |

## What counts as an incident

| Class | Examples | Notify the municipality contact |
|---|---|---|
| **A. Personal-data breach** (confirmed or suspected) | A leaked `.env`, database dump or backup; an unauthorised sign-in to an admin account; a defaced or tampered record; an accepted exploit of a patched-late advisory; a mis-published contract that exposes personal data | Yes, always: [Breach notification](#breach-notification-gdpr-art-33) |
| **B. Security event without confirmed data exposure** | A vulnerability being actively exploited upstream; a leaked token that was rotated before use; a failed intrusion attempt in the logs | Yes, informally, once the facts are known |
| **C. Availability incident** | Stack down, deep health check failing, failed backup, stalled CRZ sync | Only if it exceeds [the outage threshold](#severity-and-response-targets) |

The test for class A is the GDPR definition: a breach of security leading to accidental or unlawful destruction, loss, alteration, unauthorised disclosure of, or access to personal data. **Loss counts**: an unrecoverable database is a breach when it holds personal data. When unsure, treat it as class A and downgrade later.

What personal data a stack holds (the categories in the DPA template, see [Related documents](#related-documents)): Decidim user accounts of the municipality's staff (name, e-mail, password hash, IP and access timestamps), contact persons named in contract records, and whatever the municipality typed into contract text or attachments. Contract records are public once published; **unpublished drafts, review notes and attachments are not**.

## Severity and response targets

These are the targets the maintainer commits to for the pilot. The alert levels are the ones Alertmanager already emits ([observability.md](observability.md#alerts)); the response times are policy and are measured from the alert or the report, whichever is first.

| Severity | Trigger | Acknowledge | Contain / restore service | Inform municipality contact |
|---|---|---|---|---|
| **S1 critical** | Alert `AppUptimeCritical` or `HttpErrorRateCritical`; confirmed class A breach | 1 h (08:00-22:00 `Europe/Bratislava`), otherwise next morning | Start immediately; recover from [restore-runbook.md](restore-runbook.md) if data is lost (RPO ≤ 24 h) | Class A: **as soon as it is established that personal data is affected, and in any case within 48 h** of the maintainer becoming aware (the DPA template, art. 5(e)). Outage: after 4 h without recovery |
| **S2 high** | Alert `AppUptimeHigh`, `HttpErrorRateHigh`, `BackupStale`, `CrzSyncStale`; suspected class A or B | Same working day | Within 1 working day | Class A or B: as for S1. Others: in the next regular report |
| **S3 warning** | Alert `DeepHealthCheckFailing`, `CrzSyncNeverSucceeded` | Next working day | Within the week | Not needed unless it recurs |

Alertmanager sends critical and high alerts to Telegram and e-mail, warnings to e-mail only, and repeats an unresolved alert every 4 h (`observability/alertmanager/alertmanager.yml`). The hours above are a staffing statement, not a monitoring claim: the stack alerts around the clock, the maintainer answers inside them.

**The clock that matters** is the controller's: GDPR art. 33 gives the *municipality* 72 hours from becoming aware of a breach to notify the supervisory authority. The processor must tell the controller "without undue delay" (art. 33(2)); the DPA template fixes 48 h as the outer limit. Do not use the 48 h: tell the municipality contact the same day the breach is established, so the municipality keeps the most of its 72 h.

## Response procedure

1. **Detect and record.** Open a private incident note (date, time and timezone of detection, who or what detected it, first symptoms). Note times in `Europe/Bratislava` and UTC. Do not put secret values, personal data or full payloads in the note (see [log-policy.md](log-policy.md)).
2. **Preserve evidence before changing anything.** Container logs rotate quickly: `app` keeps at most 5 files of 10 MB, `db` and `redis` 3 files of 10 MB ([log-policy.md](log-policy.md)). Run `docker compose logs --no-color --timestamps > <incident>/logs-<service>.txt` per service and copy `/var/lib/docker/containers/<id>/<id>-json.log*`. Take an extra backup with `scripts/backup.sh` and keep it outside the prune rotation (`scripts/backup_prune.sh` keeps 7 daily / 4 weekly / 6 monthly and would eventually remove it). Export the relevant GlitchTip events. Keep all of it at mode 0700: it is personal-data material ([restore-runbook.md](restore-runbook.md#scheduled-operation)).
3. **Triage.** Decide class and severity (tables above). Establish what is known: what happened, since when, which systems, whether personal data was involved and which categories.
4. **Contain.** Pick what applies:
   - leaked or suspect secret: rotate it using the procedure and inventory in [secrets.md](secrets.md); rotation first, history rewrite second. Rotating `SECRET_KEY_BASE` invalidates all sessions, which is also the way to force every user out. After a suspected compromise rotating it is expected ([restore-runbook.md](restore-runbook.md#preconditions));
   - compromised admin account: reset its credentials and, if needed, remove its admin role in `/admin` → Participants → Admins (README, pilot checklist step 4); rotating `SECRET_KEY_BASE` also ends its sessions. Then review that person's activity in the audit trail (see [Reconstructing who did what](#reconstructing-who-did-what));
   - compromised host or container: take the stack off the public network (`docker compose stop app`), keep `db` for forensics, rebuild from a clean image rather than cleaning in place;
   - bad deploy: roll back to the last known good release (revert, redeploy through `scripts/deploy.sh`; step list in the CI/CD plan's *Rollback Procedure*, see [Related documents](#related-documents)).
5. **Assess the breach** (class A). Fill the facts the notification template asks for: categories and approximate number of data subjects and records, likely consequences, measures taken. Use the audit trail, access logs, backups and GlitchTip, and write down what is **unknown** instead of guessing.
6. **Notify** the municipality contact using [the template](#template-1-sprostredkovateľ-prevádzkovateľ-notification-to-the-municipality). A first notice with incomplete facts is correct: art. 33(4) allows information to be provided in phases.
7. **Eradicate and recover.** Fix the root cause, patch ([security-updates.md](security-updates.md)), restore from backup if needed ([restore-runbook.md](restore-runbook.md)), deploy through `scripts/deploy.sh` (backup-gated, ends with a `/healthz` check), then watch Prometheus targets and alerts for at least a day.
8. **Close with a post-incident record** within 5 working days: timeline, cause, impact, what worked, what changes. Store it with the incident note. Every breach, **including those not reported to the authority**, is recorded: art. 33(5) requires the controller to document facts, effects and remedial action, and the DPA template commits the processor to keep a breach record. A process fix becomes a platform issue in `civora-org/civora-platform`.

## Breach notification (GDPR art. 33)

| Step | Who | Deadline | Content |
|---|---|---|---|
| Notice to the controller | Maintainer to municipality contact | Without undue delay, DPA outer limit 48 h from awareness | [Template 1](#template-1-sprostredkovateľ-prevádzkovateľ-notification-to-the-municipality) |
| Notification to the supervisory authority | Municipality (controller), unless the breach is unlikely to result in a risk to the rights and freedoms of persons | 72 h from the controller becoming aware; later notices need reasons for the delay | [Template 2](#template-2-prevádzkovateľ-úrad-draft-for-the-municipality) |
| Message to data subjects | Municipality (controller), when the risk is **high** (art. 34) | Without undue delay | Plain language: what happened, likely consequences, measures, contact point |

The decision to notify the authority and the data subjects belongs to the **controller**; the maintainer supplies facts, evidence and a draft, and says clearly when the maintainer believes the risk threshold is met. In Slovakia the supervisory authority is the Úrad na ochranu osobných údajov Slovenskej republiky; the Slovak implementation of art. 33 and 34 is in zákon č. 18/2018 Z. z. about personal-data protection. Always use the authority's current notification channel and form; this repository does not hold their address.

Controller phone and e-mail go in the signed agreement. In the templates they appear as placeholders. Never commit a filled-in copy.

### Template 1: sprostredkovateľ to prevádzkovateľ (notification to the municipality)

```text
Predmet: Oznámenie porušenia ochrany osobných údajov — [Civora Zmluvy], [názov obce], č. incidentu [INC-ROK-NN]

Dobrý deň, [oslovenie kontaktnej osoby obce],

na základe zmluvy o spracúvaní osobných údajov č. [___/2026] (čl. 5 písm. e)) Vás informujem o porušení ochrany osobných údajov pri prevádzke aplikácie Civora Zmluvy pre [názov obce].

1. Stav oznámenia: [prvé oznámenie / doplnenie / záverečné oznámenie]
2. Čas zistenia porušenia: [dátum a čas, časové pásmo]; odhadovaný začiatok: [dátum a čas alebo „zatiaľ nezistený“]
3. Čo sa stalo (stručný popis povahy porušenia): [napr. neoprávnený prístup k účtu, strata/únik zálohy, výpadok s nenávratnou stratou údajov]
4. Dotknuté kategórie osobných údajov: [napr. identifikačné údaje zamestnancov obce, prihlasovacie údaje, kontaktné údaje osôb v zmluvách, prílohy]
5. Dotknuté kategórie a približný počet osôb: [údaj alebo „zatiaľ nezistený“]
6. Približný počet dotknutých záznamov: [údaj alebo „zatiaľ nezistený“]
7. Dôvernosť / integrita / dostupnosť: [ktorá z nich bola porušená]
8. Pravdepodobné následky: [popis]
9. Prijaté opatrenia (zadržanie, náprava): [zoznam]
10. Navrhované opatrenia na zmiernenie nepriaznivých následkov: [zoznam]
11. Čo zatiaľ nie je známe a kedy dostanete ďalšiu správu: [popis, termín]
12. Moje posúdenie rizika pre práva a slobody osôb: [nízke / pravdepodobne riziko / vysoké riziko] — konečné posúdenie a rozhodnutie o oznámení úradu a dotknutým osobám je na Vás ako prevádzkovateľovi.

Dôkazy (logy, zálohy, záznamy) mám zabezpečené a sprístupním ich na požiadanie. Súčinnosť pri oznámení úradu poskytnem; návrh oznámenia úradu prikladám.

Kontakt na mňa pre tento incident: [telefón], [e-mail]

S pozdravom,
[funkcia: prevádzkovateľ platformy], [pre Civora]
```

### Template 2: prevádzkovateľ to Úrad (draft for the municipality)

The municipality files this itself. The maintainer prepares the facts in this order so the municipality can copy them into the authority's current form.

```text
Oznámenie porušenia ochrany osobných údajov podľa čl. 33 Nariadenia (EÚ) 2016/679

Prevádzkovateľ: [názov obce], IČO [___], sídlo [___]
Kontaktná osoba / zodpovedná osoba: [meno/funkcia], [telefón], [e-mail]
Sprostredkovateľ: [Civora / názov], IČO [___]
Dátum a čas, kedy sa prevádzkovateľ o porušení dozvedel: [dátum a čas]
Dátum a čas oznámenia: [dátum a čas]
Dôvod omeškania, ak oznámenie nebolo podané do 72 hodín: [popis alebo „neplatí“]

1. Povaha porušenia (dôvernosť / integrita / dostupnosť) a popis udalosti: [popis]
2. Kategórie a približný počet dotknutých osôb: [údaj]
3. Kategórie a približný počet dotknutých záznamov: [údaj]
4. Pravdepodobné následky porušenia: [popis]
5. Prijaté alebo navrhované opatrenia vrátane opatrení na zmiernenie následkov: [popis]
6. Budú dotknuté osoby informované (čl. 34)? [áno, kedy a ako / nie, dôvod]
7. Informácie, ktoré zatiaľ nie sú k dispozícii, a termín doplnenia: [popis]
```

## Reconstructing who did what

The engine keeps an append-only audit trail of every admin lifecycle action: organization, acting admin user, target record, action name and timestamps; no payload, no before/after values. Per the engine's domain notes, events cannot be edited through the model; raw SQL and bulk deletes can bypass it, so treat it as evidence of normal behaviour, not as tamper-proof. The viewer is `/contracts/admin/audit_events` (filter with `?contract_id=`), visible to anyone holding an engine role. Documentation, linked by URL because the engine lives in a separate repository:

- [Audit events: model, columns, append-only design](https://github.com/civora-org/decidim-contracts_sk/blob/v1.6.0/docs/contracts-domain-notes.md) (section *Audit events*)
- [Roles, permissions and the four-eyes rule (`*_self` actions)](https://github.com/civora-org/decidim-contracts_sk/blob/v1.6.0/docs/roles-and-permissions.md)

The trail covers contract actions only. Sign-ins, account changes and requests are not in it: use Decidim's own admin action log (the `decidim_action_logs` table the engine's domain notes refer to), the container logs and GlitchTip for those, and remember that logs deliberately carry no request bodies or personal payloads ([log-policy.md](log-policy.md)), so some questions will not be answerable. State that openly in the notification.

## Rehearsal

- After every restore drill ([restore-drill-log.md](restore-drill-log.md), quarterly), spend 15 minutes walking this document with a fictional incident (leaked backup) and fix what is unclear.
- Before the first pilot go-live, send Template 1 once to a test mailbox to confirm the channel works.
- Re-read this document after any real incident and after any change to alerting, backups or the DPA.

## Known gaps

- **Single maintainer.** No backup maintainer exists, so the response targets assume availability. Name a second person before more than one municipality is live.
- **Alerts reach one person.** Telegram and e-mail receivers are both owned by the maintainer ([observability.md](observability.md#alerts)); there is no escalation path.
- **Backups are not yet encrypted or replicated offsite** ([restore-runbook.md](restore-runbook.md#scheduled-operation)). A stolen host or backup copy is therefore a class A incident with full content exposure. Closing this is the single biggest breach-impact reduction available.
- **The DPA template and this stack differ on backups.** The template's annex promises daily encrypted backups with 30-day retention stored separately from production; the stack runs 7 daily / 4 weekly / 6 monthly, unencrypted, on the host. Align one or the other before signing (tracked in the notes for civora-org/civora-platform#136).
- **No TLS terminator yet** (`DECIDIM_FORCE_SSL=0`, README *Current limitations*): until the pilot reverse proxy is in place, traffic is not encrypted in transit.
- **Auth-level events** (sign-in failures, account takeovers) have no dedicated alert.

## Related documents

- [security-updates.md](security-updates.md): patch cadence, emergency patches, `.bundler-audit.yml` review
- [restore-runbook.md](restore-runbook.md): backups, restore, drills; [restore-drill-log.md](restore-drill-log.md)
- [observability.md](observability.md): alerts, routing, GlitchTip; [log-policy.md](log-policy.md): what logs hold
- [secrets.md](secrets.md): inventory and rotation procedure
- Platform repository (civora-org/civora-platform): `docs/06-sales/dpa-zoou-template.sk.md` (processing-agreement template; art. 5(e) 48 h notice, annex 1 *Incidenty*), `docs/05-operations/civora-ci-cd-plan.md` (*Rollback Procedure*), `docs/04-security/civora-threat-model.md`
