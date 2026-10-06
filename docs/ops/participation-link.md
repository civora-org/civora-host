# Participation link

Contracts can be linked to Decidim **Accountability results** and **Budgets projects**, and the linked contracts show up on those pages, so a resident can follow *project, result, contract* (civora-org/civora-platform#130, #131; epic #142; ADR-009: engine-owned join, host resolver). The engine ships the join and the "Related contracts" block; this host supplies the resolver and the two view overrides. No migration, no Decidim core change.

## What the host contains

| Piece | File |
|---|---|
| Whitelist and resolver wiring | `config/initializers/contracts_sk.rb` |
| Organization-scoped resolver | `app/lib/participation_link_resolver.rb` |
| Result page override | `app/views/decidim/accountability/results/_project.html.erb` |
| Budgets project page override | `app/views/decidim/budgets/projects/show.html.erb` |
| Tests | `test/lib/participation_link_resolver_test.rb`, `test/integration/related_contracts_views_test.rb` |

`decidim-accountability` and `decidim-budgets` come with the `decidim` meta-gem (0.31.7); nothing was added to the Gemfile. The Accountability and Budgets **components** must still exist in a participatory process of the organization.

## Resolver rules

`ParticipationLinkResolver` answers `{ label:, url: }` (a relative path), or nil, which hides the link on the public contract page and flags it in admin. It answers nil unless:

- the target type is `Decidim::Accountability::Result` or `Decidim::Budgets::Project`;
- the target's organization is the **contract's** organization (a bare id lookup is not tenant-safe: another tenant's id never resolves);
- the component is published and the participatory space is published and not private (the label is rendered publicly);
- the target still exists (soft-deleted targets are dangling).

The related-contracts block on the Decidim page is the reverse lookup: published contracts of the page's organization only, nothing rendered when none.

## Linking a contract (admin)

1. Find the numeric id: open the result (or project) in the public site; the id is the last number in the URL, e.g. `/processes/<slug>/f/12/results/34` is result **34**, `/processes/<slug>/f/13/budgets/5/projects/7` is project **7**.
2. Sign in as a user holding the `editor` role, open `/contracts/admin/contracts`, edit a contract that is still editable (for example a draft).
3. In the **Links** card choose the **Target type** (`Decidim::Accountability::Result` or `Decidim::Budgets::Project`), enter the **Target id**, and add. The row shows the resolved title as a link; "Target no longer available" means the id does not resolve (wrong id, other organization, unpublished space, deleted target): remove it and fix the id.
4. Once the contract is published, its public page lists the link, and the result/project page lists the contract.

## Upgrading Decidim

The two view overrides are verbatim copies of the gem views plus one marked line (`<%# Civora %>`), headed with the Decidim version. `test/integration/related_contracts_views_test.rb` compares them with the installed gems and fails on drift. On a Decidim bump: re-copy both files from the gem (`bundle info decidim-accountability --path`, `decidim-budgets`), re-add the line, update the version in the header.
