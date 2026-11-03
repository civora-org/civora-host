# Appearance — Slovak public-sector visual identity (Stage 2)

This document records the demo-stack appearance values for the Civora host app so
the visual identity is reproducible from a clean install. It belongs to Stage 2 of
[civora-org/civora-platform#82]: the `decidim-contracts_sk` engine stays
markup-only; the identity (colors, logo, print behaviour) lives in this host app
as organization data and host-level assets.

## Organization colors

The palette is organization data, not stylesheet constants. Decidim stores it in
`Decidim::Organization#colors` and exposes it to CSS as custom properties on
`:root` (`--primary`, `--secondary`, `--tertiary`, plus `-rgb` triplet variants)
via `Decidim::OrganizationHelper#organization_colors`, rendered by
`app/views/layouts/decidim/_organization_colors.html.erb` in decidim-core. The
host `tailwind.config.js` consumes the `-rgb` variants through its `withOpacity`
helper (`primary: withOpacity("--primary-rgb")`, …), so every `bg-primary` /
`text-secondary` utility tracks the organization's palette without any CSS
changes.

Set these exact values on the demo organization (institutional blues with a
Slovak-flag red accent):

| Key          | Value     | Usage                                       |
| ------------ | --------- | ------------------------------------------- |
| `primary`    | `#00539B` | Brand blue — buttons, links, badge, accents |
| `secondary`  | `#1F6FC0` | Lighter institutional blue — highlights     |
| `tertiary`   | `#C8102E` | Slovak-flag red — alerts and small accents  |

```ruby
# bin/rails runner
org = Decidim::Organization.first
org.colors = {
  "primary" => "#00539B",
  "secondary" => "#1F6FC0",
  "tertiary" => "#C8102E"
}
org.save!
```

## Logo

The wordmark lives at `app/packs/images/civora-logo.svg` — the "Dvere" wordmark
from civora.sk (`brand/wordmark.svg` in `civora-org/civora-site`: the open-door
mark in indigo and terracotta and the word "Civora", viewBox 210×64, transparent
ground, no external references, no scripts). It replaces the earlier blue "C"
badge with the "Verejné zmluvy" subline, which belonged to the pre-Dvere look and
sat on a white box that showed on the warm paper ground.

Attach the PNG as the organization logo — the header renders the logo through a
`:medium` variant (`organization.attached_uploader(:logo).variant_url(:medium)`),
and SVG variants depend on an `librsvg` delegate that the production image does
not ship (verified live; `convert` fails with `delegate failed 'rsvg-convert'`).
The SVG stays in the repo as the editable source; `civora-logo.png` (840×256,
transparent) is the attachable rasterization (`rsvg-convert -w 840 civora-logo.svg`).
Existing organizations keep the logo they have until it is attached again:

```bash
bin/rails runner 'org = Decidim::Organization.first; org.logo.attach(io: File.open(Rails.root.join("app/packs/images/civora-logo.png")), filename: "civora-logo.png", content_type: "image/png"); org.save!'
```

## Official URL

Set the organization `official_url` to `https://civora.example.org` for the demo
stack (placeholder domain; replace with the production domain when it exists).
This URL feeds metadata, canonical links and the footer organization link.

## Typography

See *Civora public theme* below: Alegreya Sans 700 for headings and Source Sans 3
for text, both self-hosted under `app/packs/fonts/civora/` (SIL Open Font License
1.1; the same files as civora.sk). Slovak diacritics are covered by the
`latin` + `latin-ext` / `sk-ext` subsets. Nothing loads from a third-party host.

## Print behaviour

`app/packs/stylesheets/decidim/decidim_application.scss` adds an
application-level print layer (Decidim 0.32 core ships none): on print it hides
the site header/footer region, cookie-consent banner and warning, offline
banner and session-timeout modal, forces white background/black text, removes
the responsive column insets, and applies pagination hygiene (cards, lists and
table rows stay whole; headings stay with their content; long tables keep
repeating header rows). Selectors are documented inline and were verified
against the pinned decidim-core/admin 0.32.1 gems.

## Civora public theme

*The town leads, Civora signs.* The public (participant-facing) pages of every
municipality keep that municipality's identity through its organization colours
(`--primary`, `--secondary`, `--tertiary`, set as above). Civora supplies the
foundation under them: warm paper surfaces, two typefaces, a shape language, calm
spacing and a small signature in the footer. The admin has its own chrome, below.

### Direction note

| | |
| --- | --- |
| **Idea** | A town hall's public counter: paper, ink, a clerk who respects you. Warm but strict. |
| **Surfaces** | Page ground paper `#fbf6ee`, never white. Quiet panels (filter aside, hero without image, process hero) cream `#f3e9db`. Raised surfaces (cards, dropdowns, fields) paper-light `#fdfaf6`, derived (paper half way to white). Hairlines `#e3d8c8`. Flat: no shadows, no rings. |
| **Ink** | Text `#2b2a40` (12.9:1 on paper), secondary text `#4a4660` (8.4:1) and muted `#5b576c` (6.5:1). |
| **Town colours** | Untouched. Buttons, links, the breadcrumb band, the heading underline and the header icons stay in `--primary` / `--secondary` / `--tertiary`. The hero's door and strip use the town's `--primary`; the doorway is terracotta `#b5523a`, the one warm thing on the page. |
| **Type** | Alegreya Sans 700 for h1 to h4, Source Sans 3 400 / 600 / 700 for everything else. Scale: hero `clamp(2.25rem, 1.4rem + 3.4vw, 3.75rem)`, h1 `clamp(2rem, 1.4rem + 2vw, 2.75rem)`, h2 `clamp(1.65rem, 1.3rem + 1.2vw, 2.125rem)`, h3 1.5rem, h4 1.3125rem, reading copy 1.125rem / 1.55 at a 66ch measure. Alegreya runs a little larger than Decidim's scale because its x-height is smaller. |
| **Shape** | Buttons, tags, labels, the search field and the language chooser are pills (999px). Cards, panels, fields, dropdowns are 10px. Inputs get a 3:1 edge (`#89868e`), not the decorative hairline. |
| **Spacing** | Hero: 3 to 5.5rem block padding, min-height `min(34rem, 70vh)` (Decidim: 60 to 65vh). Headings keep Decidim's rhythm; the heading underline is a 3px pill. |
| **Header** | Paper with one hairline. Links are ink; icons carry the town's accent; hover is a cream pill, not a solid fill. The breadcrumb band below it stays the town's primary. From 1024px the search is a real field (14 to 22rem, placeholder visible), the language chooser shows the locale code ("SK"; the dropdown lists full names), link gaps tighten in steps and, from 1024 to 1279px, the link icons are dropped. The desktop "Menu" button is left out while its dropdown holds only what the bar already links (contracts, processes); it returns when another item (for example assemblies) is registered. Mobile is unchanged. |
| **Hero (home)** | Without an uploaded image: cream ground, left-aligned ink title, the two calls to action, a modrotlac strip in the town's primary along the bottom and, from 1280px, a large arch ("the door") standing on it. With an image: Decidim's overlay and white title, left-aligned. |
| **Footer** | A deep band: the town's primary darkened toward ink (`color-mix(in srgb, <primary> 32%, #151428)`), so it is dark for any primary (paper text 5.8 to 13.7:1 for the palettes below). The signature, the Civora door mark in paper and terracotta with the word "Civora" linking to civora.sk, sits between the Decidim credit and the licence icons. Decidim's own credit stays. |
| **Light only** | `color-scheme: light` and an explicit paper ground. Before this, a dark-mode browser repainted the transparent page ground black under dark text. |
| **Focus** | One ring everywhere: 3px solid in the town's accent, 3px offset; paper on the footer band and the breadcrumb band. |
| **Motion** | None added. `prefers-reduced-motion` shortens transitions to nothing. |

### Where it lives

| Layer | File | What it holds |
| --- | --- | --- |
| Tokens and Tailwind | `config/tailwind.config.js.erb` | Decidim's Tailwind template, copied. Neutrals (`black`, `gray*`, `background*`), `fontFamily.sans` / `display` and `borderRadius.DEFAULT` read `var(--civora-…, <Decidim's value>)`. |
| Fonts | `app/packs/fonts/civora/` and `app/packs/stylesheets/decidim/civora/_fonts.scss` | Eight woff2 files, the `@font-face` rules, `OFL.txt`. |
| Foundation | `app/packs/stylesheets/decidim/civora/_foundation.scss` | `:root` tokens, the `-rgb` triplets the Tailwind template reads, paper ground, typography, focus. |
| Components | `app/packs/stylesheets/decidim/civora/_components.scss` | Header, buttons, hero, process hero, cards, labels, forms, footer and signature. |
| Entry | `app/packs/stylesheets/decidim/decidim_application.scss` | `@use`s the three files above, then the host's print layer and hero CTA rule. |

**The public pack does not reach the admin.** The `--civora-…` variables of the
public theme are defined only in the public pack (`decidim_overrides`, which
`decidim_application.scss` compiles into). Decidim's admin loads `decidim_core`
and `decidim_admin`, so every `var(--civora-…, <fallback>)` in the shared
Tailwind build resolves to the stock Decidim value there. The admin chrome is a
separate layer, next section.

## Civora admin chrome

The admin is Civora's own product surface (the clerk's desk), so the Dvere
identity leads there and the town's colours do not. Decidim's admin ignores the
organization colours anyway: `decidim-admin`'s `application.scss` hard-codes
`--primary`, `--secondary` and `--tertiary` on `:root`, so nothing a town picks
can reach the chrome or break its contrast. Direction: the "Pracovný stôl" brief
(`decidim-contracts_sk` `tmp/qa-2026-11-03/admin-redesign-brief.md`, section 1).

| | |
| --- | --- |
| **Hook** | `app/packs/stylesheets/decidim/admin/decidim_application.scss`, which replaces an empty file of the same path in `decidim-admin`. `decidim_admin_overrides.scss` `@use`s it and the admin layout links that pack after `decidim_core` and `decidim_admin` (`append_stylesheet_pack_tag`), so it wins ties by order. It `@use`s `civora/fonts` (Source Sans 3 again, the admin pack does not load the public one) and `civora/admin`, the rules. No Decidim core patch, no view override. |
| **Sidebar** | Deep indigo `#232c63`, paper text (12.1:1). Active item: paper-light pill with indigo-deep text (12.5:1). Hover: a paper wash. Focus: a 3px paper ring. Icons follow the text colour. |
| **Logo** | Always on a paper-light plate (10px corners, 8px padding). A town's logo can be any colour (navy, black, red, the Civora indigo wordmark) and none is safe on deep indigo; on a paper plate every one reads the same, so no per-organization logo variant is needed. Decidim's built-in mark (an inline SVG drawn white, used when no logo is uploaded) needs no plate on this ground. Checked live with the Civora PNG and a black square. |
| **Topbar** | Paper `#fbf6ee`, hairline `#e3d8c8` below, ink text. "Zobraziť stránku" is a quiet outlined control; the language switch and user menu stay in ink. Replaces the yellow `--tertiary` bar. |
| **Breadcrumb band** | Was a slate bar with white text. Now on the page ground with a hairline, ink path, indigo links. The "Správa" menu trigger beside it is the same quiet outlined control (Decidim's `.button:hover` turns it white on a dark overlay; the rule out-ranks that). |
| **Ground and panels** | Page paper, panels paper-light with a hairline and 8px corners (form cards, table wrappers); the white secondary-nav wrapper is dropped so panels are one level deep. Sticky save bar: paper-light, hairline above, the save button filled indigo. |
| **Action colour** | `--primary` and `--secondary` are set to Dvere indigo `#34408a` for the admin only (they were red and blue), so every `.button__primary`, `.button__secondary` and `text-secondary` link reads as one action colour (white on indigo 9.4:1, indigo on paper 8.7:1). `--tertiary` is left alone (the colour-picker swatches read it). |
| **Controls** | Inputs, selects and textareas: 1px `#89868e` edge (3.4:1 on paper-light; Decidim's `#e5e5e5` on `#fafbfc` is 1.2:1, under WCAG 1.4.11), paper-light fill, 6px corners, an indigo ring on focus. |
| **Type** | Source Sans 3 (400, 600, 700, the files the public theme ships). |
| **Not here** | The engine's own admin screens keep their `.cs-admin-*` styles (white blocks on the contracts home are the engine's, restyled in the engine PRs of the brief). |

Selectors depend on Decidim's admin markup (`.layout-nav`, `.main-nav`, `.logo`,
`.title-bar`, `.process-title`, `.item__edit-sticky`, `.item_show__wrapper`). If a
Decidim bump renames one, that part falls back to stock Decidim: the page stays
correct, just unthemed. `test/integration/theme_override_drift_test.rb` guards the
hook itself.

### Overridden Decidim files (each one is an upgrade risk)

| File | Copied from | Change | Drift guard |
| --- | --- | --- | --- |
| `app/views/layouts/decidim/footer/_mini.html.erb` | decidim-core 0.32.1 `app/views/layouts/decidim/footer/_mini.html.erb` | One block between `<%# Civora: start %>` and `<%# Civora: end %>` renders `footer/_civora_signature`. | `test/integration/theme_override_drift_test.rb` |
| `app/views/layouts/decidim/header/_main_language_chooser.html.erb` | decidim-core 0.32.2 `app/views/layouts/decidim/header/_main_language_chooser.html.erb` | One block between `<%# Civora: start %>` and `<%# Civora: end %>` renders the locale code and keeps the full name (hidden visually on desktop, shown on mobile). | `test/integration/header_override_drift_test.rb` |
| `app/views/layouts/decidim/header/_main_links_desktop.html.erb` | decidim-core 0.32.2 (same path) | Help, Contracts and Participation links, plus a guard that leaves out the "Menu" button while it duplicates the bar (three marked blocks). | `test/integration/header_override_drift_test.rb` |
| `config/tailwind.config.js.erb` | decidim-core 0.32.1 `lib/decidim/assets/tailwind/tailwind.config.js.erb` | The lines marked `Civora:` (neutrals, font families, radius), plus a helper. | `test/integration/theme_override_drift_test.rb` |
| `app/packs/stylesheets/decidim/admin/decidim_application.scss` | decidim-admin 0.32.2 (same path; an empty hook meant to be replaced) | The admin chrome: `@use`s `civora/fonts` and `civora/admin`. | `test/integration/theme_override_drift_test.rb` |

New, not an override: `app/views/layouts/decidim/footer/_civora_signature.html.erb`.
The header, hero and cards are restyled by CSS only. The earlier overrides
(`_main_links.html.erb`, `_main_links_desktop.html.erb`, `_main_search.html.erb`,
`hero/cta_button.erb`) are unchanged.

### Selectors that depend on Decidim's markup

The no-image hero is detected with `.hero__container[style*="url('')"]` (Decidim
writes `style="--hero-image:url('')"`) and the no-banner process hero with
`[data-process-hero]:not([style])`. If Decidim changes either, the hero falls back
to Decidim's stock overlay: the page stays correct, just stock.

### Accessibility

The organization's colours are the town's choice, as in stock Decidim: white text
on `--primary` / `--secondary` buttons and the breadcrumb band needs 4.5:1, and
`--secondary` links need 4.5:1 on paper `#fbf6ee` (and on cream `#f3e9db` where
they sit on a quiet panel). The theme's own text and surfaces are tested in
`test/integration/civora_theme_test.rb`; the table is what a town can expect.

| Palette | white on primary | primary on paper | primary on cream | footer band | paper on band |
| --- | --- | --- | --- | --- | --- |
| Demo and Vranov `#00539B` | 7.8 | 7.2 | 6.5 | `#0e284d` | 13.7 |
| `#1F6FC0` (the demo's secondary) | 5.1 | 4.8 | 4.3 (use on paper only) | | |
| `#C8102E` | 5.9 | 5.5 | 4.9 | `#4e132a` | 13.5 |
| Dvere indigo `#34408A` | 9.4 | 8.7 | 7.8 | | |
| `#FFD700` (stress case) | n/a (needs dark text) | | | `#60521b` | 7.2 |

A ticked filter row (clay tint) uses ink text, never `--secondary`. Inputs have a
3:1 edge. Focus is visible on every control. An in-browser contrast pass over the
home page, a process, a proposals list, the contracts catalogue and a static page
found one failure, in Decidim's stock language chooser (neutral-500 on paper,
4.4:1), which the theme fixes.

### The contracts engine

From v1.11.0 the catalogue and the contract pages (`decidim-contracts_sk`) read the
theme's `--civora-*` custom properties through their own `--cs-*` tokens, with
fallbacks to the engine's previous values, so they match the theme here and look
unchanged on hosts without it. The engine's own Civora credit line
(`shared/_civora_credit`) hides itself on public pages when the footer carries the
host's signature (`.civora-sign`); the admin home keeps it. See "Public look and
the Civora credit" in the engine README.

## Non-goals

- **No per-engine CSS in the host.** The `decidim-contracts_sk` engine ships its
  own stylesheet; the host theme does not restyle it.
- **No per-town admin theming.** The admin chrome is Civora's, the same for every
  town; the organization colours do not reach it. Only the logo is the town's.
