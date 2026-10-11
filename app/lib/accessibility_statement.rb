# frozen_string_literal: true

require "erb"

# Accessibility statement ("Vyhlásenie o prístupnosti", sk + en) for one
# organization, stored as a Decidim static page (civora-org/civora-platform#133).
# The structure follows the EU model statement (Commission Implementing
# Decision (EU) 2018/1523): compliance status, non-accessible content, date of
# preparation, feedback and contact, enforcement procedure.
#
# Idempotent: the page is found by (organization, slug) and rewritten, so a
# re-run after an audit updates the text and never duplicates the page. Edits
# made in the Decidim admin to this page are overwritten by the next run, so
# change the text here, not in the admin (docs/ops/accessibility-statement.md).
#
# Honesty rules for the text below: it states only what the automated audit
# showed and says plainly what has not been tested yet. Update FINDINGS and
# PREPARED_ON together after each re-audit.
class AccessibilityStatement
  SLUG = "accessibility"
  PREPARED_ON = Date.new(2026, 10, 11)
  CONTACT_PLACEHOLDER = { "sk" => "[doplniť kontaktný e-mail]", "en" => "[add the contact e-mail]" }.freeze
  VERIFY = { "sk" => "[overiť s právnikom]", "en" => "[to be verified with a lawyer]" }.freeze
  DATE_TEXT = { "sk" => "11. októbra 2026", "en" => "11 October 2026" }.freeze
  TITLE = { "sk" => "Vyhlásenie o prístupnosti", "en" => "Accessibility statement" }.freeze
  LOCALES = %w(sk en).freeze

  Result = Struct.new(:page, :created, :contact_email, keyword_init: true)

  # contact_email: explicit address (the rake task passes ACCESSIBILITY_CONTACT_EMAIL);
  # without it the organization's own sender address is used, and without that
  # the text carries a visible placeholder instead of an invented address.
  def self.call(organization, contact_email: nil)
    new(organization, contact_email).call
  end

  def initialize(organization, contact_email)
    @organization = organization
    @contact_email = contact_email.to_s.strip.presence || organization_contact
  end

  def call
    page = Decidim::StaticPage.find_or_initialize_by(organization: @organization, slug: SLUG)
    created = page.new_record?
    page.title = LOCALES.index_with { |locale| TITLE.fetch(locale) }
    page.content = LOCALES.index_with { |locale| content(locale) }
    page.allow_public_access = true
    page.save!
    Result.new(page: page, created: created, contact_email: @contact_email)
  end

  def content(locale)
    send("content_#{locale}")
  end

  private

  def organization_contact
    settings = @organization.smtp_settings.to_h
    settings["from_email"].to_s.strip.presence
  end

  def contact_html(locale)
    return ERB::Util.h(CONTACT_PLACEHOLDER.fetch(locale)) if @contact_email.blank?

    address = ERB::Util.h(@contact_email)
    %(<a href="mailto:#{address}">#{address}</a>)
  end

  def organization_name(locale)
    name = @organization.name
    ERB::Util.h((name[locale].presence || name.values.compact_blank.first).to_s)
  end

  def content_sk
    <<~HTML
      <p>#{organization_name("sk")} sa zaväzuje sprístupniť register verejných zmlúv Civora (webové sídlo na adrese #{ERB::Util.h(@organization.host)}) v súlade so smernicou (EÚ) 2016/2102 a so slovenskými predpismi, ktoré ju preberajú #{VERIFY["sk"]}. Toto vyhlásenie o prístupnosti sa vzťahuje na verejný katalóg zmlúv a na administráciu zmlúv.</p>

      <h2>Stav súladu</h2>
      <p>Webové sídlo je <strong>čiastočne v súlade</strong> s normou EN 301 549 V3.2.1 (zahŕňa požiadavky WCAG 2.1 úrovne AA). Dôvody nesúladu sú uvedené nižšie. Hodnotenie je vlastné (sebahodnotenie), nie nezávislý audit.</p>

      <h2>Neprístupný obsah</h2>
      <p>Obsah uvedený nižšie nie je plne prístupný.</p>
      <h3>Nesúlad s normou</h3>
      <ul>
        <li>Administrácia (prihlásení zamestnanci): hlavná navigácia administračného rozhrania platformy Decidim používa nesprávnu štruktúru rolí ARIA a zoznamov a na úzkych obrazovkách má tlačidlo menu bez prístupného názvu. Ide o súčasť jadra Decidim, nie o kód registra zmlúv; chybu nahlasujeme dodávateľovi platformy. Verejné stránky sa jej netýkajú.</li>
        <li>Prílohy k zmluvám (dokumenty, ktoré sa zverejňujú) sa zverejňujú vo formáte, v akom ich poskytla zmluvná strana alebo CRZ; nemusia byť označkované a čitateľné čítačkou obrazovky (napríklad skenované PDF).</li>
      </ul>
      <h3>Ešte neotestované</h3>
      <ul>
        <li>Zatiaľ sme nevykonali manuálne testovanie čítačkou obrazovky (NVDA, VoiceOver) ani úplné testovanie len klávesnicou. Doterajšie výsledky pochádzajú z automatizovaného nástroja axe-core, ktorý zachytí len časť kritérií WCAG. Výsledok manuálnych testov doplníme a toto vyhlásenie aktualizujeme.</li>
      </ul>
      <h3>Mimo požiadaviek normy WCAG 2.1</h3>
      <ul>
        <li>Niektoré odkazy v hlavičke a pätičke (napríklad prihlásenie a odkazy v pätičke) majú cieľ menší ako 24 × 24 px. Požiadavka sa objavuje až vo WCAG 2.2 (kritérium 2.5.8); uvádzame ju pre úplnosť a budeme ju riešiť.</li>
      </ul>

      <h2>Príprava tohto vyhlásenia</h2>
      <p>Vyhlásenie bolo pripravené <time datetime="#{PREPARED_ON.iso8601}">#{DATE_TEXT["sk"]}</time> na základe sebahodnotenia. Použili sme automatizovanú kontrolu axe-core (pravidlá WCAG 2.0/2.1 úrovne A a AA) na stránkach: katalóg zmlúv, detail zmluvy, štatistiky, administrácia (prehľad, zoznam, úprava, strany, audit), a to pri šírke 1440 px aj 375 px. Na verejných stránkach neboli nájdené žiadne vážne ani kritické nedostatky.</p>

      <h2>Spätná väzba a kontakt</h2>
      <p>Ak narazíte na prekážku v prístupnosti alebo potrebujete obsah v inej forme, napíšte nám na #{contact_html("sk")}. Uveďte adresu stránky, popis problému a prípadne používanú asistenčnú technológiu.</p>

      <h2>Postup presadzovania</h2>
      <p>Ak neobdržíte uspokojivú odpoveď, môžete sa obrátiť na príslušný dohľadový orgán Slovenskej republiky pre prístupnosť webových sídel verejného sektora #{VERIFY["sk"]}.</p>
    HTML
  end

  def content_en
    <<~HTML
      <p>#{organization_name("en")} is committed to making the Civora public contracts register (the website at #{ERB::Util.h(@organization.host)}) accessible, in accordance with Directive (EU) 2016/2102 and the Slovak rules that transpose it #{VERIFY["en"]}. This accessibility statement applies to the public contract catalogue and to the contract administration.</p>

      <h2>Compliance status</h2>
      <p>This website is <strong>partially compliant</strong> with EN 301 549 V3.2.1 (which includes the WCAG 2.1 level AA requirements), because of the non-compliances listed below. The assessment is a self-assessment, not an independent audit.</p>

      <h2>Non-accessible content</h2>
      <p>The content listed below is not fully accessible.</p>
      <h3>Non-compliance with the standard</h3>
      <ul>
        <li>Administration (signed-in staff): the main navigation of the Decidim administration interface uses an incorrect ARIA role and list structure, and on narrow screens its menu button has no accessible name. This is part of Decidim core, not of the contracts register code; we are reporting it to the platform vendor. The public pages are not affected.</li>
        <li>Contract attachments (the documents that are published) are published in the format supplied by the contracting party or by CRZ; they may not be tagged or readable by a screen reader (for example scanned PDFs).</li>
      </ul>
      <h3>Not yet tested</h3>
      <ul>
        <li>We have not yet carried out manual testing with a screen reader (NVDA, VoiceOver) or a complete keyboard-only test. Results so far come from the automated axe-core tool, which detects only part of the WCAG criteria. We will add the outcome of the manual tests and update this statement.</li>
      </ul>
      <h3>Beyond the WCAG 2.1 requirements</h3>
      <ul>
        <li>Some links in the header and footer (for example sign-in and footer links) have a target smaller than 24 × 24 px. This requirement appears only in WCAG 2.2 (criterion 2.5.8); we list it for completeness and will address it.</li>
      </ul>

      <h2>Preparation of this statement</h2>
      <p>This statement was prepared on <time datetime="#{PREPARED_ON.iso8601}">#{DATE_TEXT["en"]}</time> on the basis of a self-assessment. We ran the automated axe-core check (WCAG 2.0/2.1 level A and AA rules) on these pages: contract catalogue, contract detail, statistics, and the administration (overview, list, edit, parties, audit trail), at 1440 px and 375 px width. No serious or critical issues were found on the public pages.</p>

      <h2>Feedback and contact</h2>
      <p>If you meet an accessibility barrier or need content in another form, write to us at #{contact_html("en")}. Please include the page address, a description of the problem and the assistive technology you use.</p>

      <h2>Enforcement procedure</h2>
      <p>If you do not receive a satisfactory reply, you can contact the competent supervisory body of the Slovak Republic for the accessibility of public-sector websites #{VERIFY["en"]}.</p>
    HTML
  end
end
