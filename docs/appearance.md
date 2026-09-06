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

The wordmark lives at `app/packs/images/civora-logo.svg` — a standalone SVG
(rounded #00539B badge with a white "C" monogram, "Civora" wordmark in #1E293B
and a "Verejné zmluvy" subline in #00539B; viewBox 360×96, no external
references, no scripts).

Attach the PNG as the organization logo — the header renders the logo through a
`:medium` variant (`organization.attached_uploader(:logo).variant_url(:medium)`),
and SVG variants depend on an `librsvg` delegate that the production image does
not ship (verified live; `convert` fails with `delegate failed 'rsvg-convert'`).
The SVG stays in the repo as the editable source; `civora-logo.png` (720×192) is
the attachable rasterization:

```bash
bin/rails runner 'org = Decidim::Organization.first; org.logo.attach(io: File.open(Rails.root.join("app/packs/images/civora-logo.png")), filename: "civora-logo.png", content_type: "image/png"); org.save!'
```

## Official URL

Set the organization `official_url` to `https://civora.example.org` for the demo
stack (placeholder domain; replace with the production domain when it exists).
This URL feeds metadata, canonical links and the footer organization link.

## Typography

Typography intentionally stays on Decidim 0.31 defaults (Source Sans Pro with
system sans fallbacks, per the host `tailwind.config.js`). Slovak diacritics
(ľ š č ť ž ý á í é ú ä ô ň) are fully covered by the default stack. **No font
files are shipped** with the host app — adding custom webfonts is out of scope.

## Print behaviour

`app/packs/stylesheets/decidim/decidim_application.scss` adds an
application-level print layer (Decidim 0.31 core ships none): on print it hides
the site header/footer region, cookie-consent banner and warning, offline
banner and session-timeout modal, forces white background/black text, removes
the responsive column insets, and applies pagination hygiene (cards, lists and
table rows stay whole; headings stay with their content; long tables keep
repeating header rows). Selectors are documented inline and were verified
against the pinned decidim-core/admin 0.31.7 gems.

## Stage-2 non-goals

- **No per-engine CSS.** The `decidim-contracts_sk` engine receives no
  engine-specific stylesheets; it ships markup that uses Decidim core classes
  and inherits the host identity.
- **Admin follows host defaults.** The admin interface keeps the stock Decidim
  admin look; no admin-specific theming in Stage 2.
