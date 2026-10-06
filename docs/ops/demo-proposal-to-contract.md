# Demo seed: from a proposal to the contract that delivered it

`civora:demo:proposal_to_contract` builds one fictional story in an existing organization (civora-org/civora-platform#132, epic #142): a resident's proposal, accepted, becomes a budget project, then an accountability result ("Realizované"), and the contract DEMO-2026-010 is linked to the result and the project (the participation link, see [participation-link.md](participation-link.md)). The Slovak click path is in civora-platform `docs/06-sales/demo-proposal-to-contract.sk.md`.

```
bin/rails "civora:demo:proposal_to_contract[<organization_id>]"   # id optional: first organization
```

It prints the URL of every step (base `http://<organization host>`, override with `DEMO_BASE_URL`).

## What it creates

| Step | Record |
|---|---|
| Process | published "Participatívny rozpočet 2026 – Obec Ukážková" (slug `participativny-rozpocet-2026-obec-ukazkova`), one active step |
| Proposals | "Nové detské ihrisko pri materskej škole", demo resident `demo-obyvatel@example.org`, accepted, answer published |
| Budgets | budget with the project "Nové detské ihrisko pri materskej škole" (25 000 EUR, selected), linked to the proposal (`included_proposals`) |
| Accountability | status "Realizované" (100 %), result with three milestones, linked to the proposal and the project |
| Contracts | published DEMO-2026-010 (23 600 EUR, supplier "Stavebná Ukážka s.r.o.", fake IČO 00000011, CRZ filing date), ContractLink to the result and to the project |

The "Zmluvy" component (#89) does not exist yet and is not seeded.

## Idempotent

Every record is found by a natural key (slug, component per process, title per component, contract reference) and created only when missing; Decidim links are written only while absent, so links added by hand survive. A second run prints "Nothing new". DEMO-2026-010 is shared with `decidim_contracts_sk:seed_demo`: whichever runs first creates it, the other leaves its content alone (only blank parties and CRZ filing fields are filled), so the order does not matter.

Fictional data only: no real town, person or company. Only the demo resident (a non-admin) and, if missing, `contracts-editor@example.org` (the contract author) are created; passwords are random and unknown.

## Run in the dev container

```
docker compose -f compose.yaml -f compose.dev.yml cp app/lib/civora_demo app:/app/app/lib/
docker compose -f compose.yaml -f compose.dev.yml cp lib/tasks/civora_demo.rake app:/app/lib/tasks/
docker compose -f compose.yaml -f compose.dev.yml exec app bin/rails "civora:demo:proposal_to_contract[1]"
```

(The service name, `/app` path and organization id may differ; check with `docker compose ps`.)

## Tests

`PARALLEL_WORKERS=1 bin/rails test test/lib/proposal_to_contract_seed_test.rb`
