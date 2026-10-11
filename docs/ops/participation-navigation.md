# Participation entry points

Residents find the participatory processes from three places. All of them appear only when the organization has at least one published process the visitor can open (the same set Decidim's `/processes` index lists; an unpublished or private process does not count). A contracts-only town keeps today's header and homepage.

| Where | What | Needs a command |
|---|---|---|
| Header (desktop) | "Participácia" / "Participation" link to `/processes`, next to Help and Contracts | no |
| Mobile menu | Decidim's own `:mobile_menu` entry "Procesy", registered by decidim-participatory_processes | no |
| Homepage hero | second button to `/processes` beside "Prezrieť zmluvy" | no |
| Homepage below the hero | Decidim's "highlighted processes" block (promoted groups, highlighted and active processes) | yes |

## What a town runs

```sh
bin/rails "civora:home:participation[<organization_id>]"
```

Without an id the first organization is used. The task creates the highlighted-processes block (6 results) as the last homepage block, published. It is idempotent and never overwrites: an existing block, including one an admin unpublished, reordered or edited in **Settings > Appearance > Homepage**, is left as it is. The block shows nothing until a process is highlighted (admin: process > "Promoted") or active.

## Notes

- Header: `app/views/layouts/decidim/header/_main_links_desktop.html.erb` (override of the core partial, see the comment in the file). The check is `ParticipationNavigation.processes?` (`app/lib/participation_navigation.rb`), memoized per request.
- Hero: `app/cells/decidim/content_blocks/hero/cta_button.erb` overrides the core cell template (0.31.7) with the original button kept verbatim plus the second one; layout in `app/packs/stylesheets/decidim/decidim_application.scss` (`.hero__cta`). On a Decidim bump compare both overrides with the gem.
- The tooltip "Podieľajte sa na procesoch platformy" on the contracts button was core's `decidim.pages.home.hero.participate_title`; the host locale files now say "Prezrieť verejné zmluvy". (The hero button target itself is `cta_button_path_*` in `db/seeds.rb`, already `/contracts`.)
