# frozen_string_literal: true

# Stopgap for decidim-contracts_sk v1.10.0: its admin menu item for the
# organisation header (civora-org/civora-platform#211) asks for the icon
# "building-line", which Decidim 0.32 core does not register, so every admin
# page that renders the sidebar raises "Icon building-line not found" in test
# and logs a deprecation elsewhere. Map the name onto the core icon
# "government-line" until the engine uses a registered icon; then delete this
# file.
Decidim.icons.register(name: "building-line", icon: "government-line", category: "system",
                       description: "Organisation header (decidim-contracts_sk)", engine: :core)
