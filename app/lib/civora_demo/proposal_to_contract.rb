# frozen_string_literal: true

module CivoraDemo
  # Demo scenario for civora-org/civora-platform#132 (epic #142): one coherent,
  # fictional story from a resident's proposal to the contract that delivered
  # it, in an EXISTING organization:
  #
  #   proposal -> budget project -> accountability result -> contract
  #
  # Run with `bin/rails "civora:demo:proposal_to_contract[<organization_id>]"`
  # (lib/tasks/civora_demo.rake). See docs/ops/demo-proposal-to-contract.md.
  #
  # Idempotent: every record is found by a stable natural key (process slug,
  # component manifest within the process, localized title within the
  # component, contract reference) and created only when missing, so a re-run
  # adds nothing. Decidim links (proposal <-> project <-> result) are written
  # only while absent, because Decidim's link_resources replaces every link of
  # the same name, which would drop links an admin added by hand. Contract
  # links use the engine's ContractLink (ADR-009), not Decidim's resource
  # links: contracts have no participatory space.
  #
  # Fictional data only: the municipality, resident, supplier and IČO are made
  # up (IČO 00000011 is a placeholder, the same one the engine's own demo seed
  # gives the play-equipment supplier). DEMO-2026-010 is also written by
  # `decidim_contracts_sk:seed_demo`; whichever runs first creates it and the
  # other leaves its content alone, so the two seeds can run in any order.
  class ProposalToContract
    PROCESS_SLUG = "participativny-rozpocet-2026-obec-ukazkova"
    CONTRACT_REFERENCE = "DEMO-2026-010"
    RESIDENT_EMAIL = "demo-obyvatel@example.org"
    EDITOR_EMAIL = "contracts-editor@example.org"
    STATUS_KEY = "realizovane"
    SUPPLIER = { name: "Stavebná Ukážka s.r.o.", ico: "00000011", address: "Murárska 7, 811 02 Bratislava" }.freeze
    BUYER = { name: "Obec Ukážková", ico: "00000004", address: "Ukážková 1, 900 00 Ukážkovo" }.freeze

    TITLES = {
      process: "Participatívny rozpočet 2026 – Obec Ukážková",
      proposal: "Nové detské ihrisko pri materskej škole",
      budget: "Participatívny rozpočet 2026",
      project: "Nové detské ihrisko pri materskej škole",
      result: "Nové detské ihrisko pri materskej škole",
      contract: "Dodávka a montáž herných prvkov na detské ihriská"
    }.freeze

    # What `call` produced, for the printed URL list and for tests.
    Result = Struct.new(:organization, :space, :proposal, :project, :result, :contract, :created, keyword_init: true)

    def self.call(organization)
      new(organization).call
    end

    def initialize(organization)
      @organization = organization
      @created = []
    end

    def call
      ActiveRecord::Base.transaction do
        resident = find_or_create_user!(RESIDENT_EMAIL, "Obyvateľka Ukážková", "demo_obyvatel", admin: false)
        editor = find_or_create_user!(EDITOR_EMAIL, "Contracts editor", "contracts_editor", admin: true)
        space = ensure_process!
        step = ensure_step!(space)
        proposal = ensure_proposal!(space, resident)
        project = ensure_project!(space, step, proposal)
        result = ensure_result!(space, proposal, project)
        contract = ensure_contract!(editor)
        ensure_contract_links!(contract, result, project)
        Result.new(organization: @organization, space: space, proposal: proposal, project: project,
                   result: result, contract: contract, created: @created)
      end
    end

    # Printable (label, path) pairs, one per step of the story, in click order.
    def self.urls(outcome)
      [
        ["Proces", path_for(outcome.space)],
        ["Návrh", path_for(outcome.proposal)],
        ["Projekt", path_for(outcome.project.budget, outcome.project)],
        ["Výsledok", path_for(outcome.result)],
        ["Zmluva", "/contracts/#{outcome.contract.id}"],
        ["Dodávateľ", "/contracts/suppliers/#{SUPPLIER[:ico]}"],
        ["Štatistika", "/contracts/statistics"]
      ]
    end

    def self.path_for(*subjects)
      Decidim::ResourceLocatorPresenter.new(subjects.length > 1 ? subjects : subjects.first).path
    end

    private

    attr_reader :organization

    def locales
      organization.available_locales.presence || %w(sk)
    end

    # The same Slovak text under every available locale: the demo is Slovak and
    # a missing translation must never blank a page.
    def loc(text)
      locales.index_with { text }
    end

    def sk(translated)
      translated.is_a?(Hash) ? translated["sk"] || translated.values.first : translated
    end

    def created!(record)
      @created << "#{record.class.name} ##{record.id}"
      record
    end

    def find_or_create_user!(email, name, nickname, admin:)
      user = Decidim::User.find_by(email: email, organization: organization)
      return user if user

      created! Decidim::User.create!(
        email: email, organization: organization, name: name, nickname: nickname,
        tos_agreement: "1", accepted_tos_version: organization.tos_version,
        password: SecureRandom.hex(16), # intentionally unknown; reset via the host app
        confirmed_at: Time.current,
        admin: admin, admin_terms_accepted_at: (Time.current if admin)
      )
    end

    def ensure_process!
      Decidim::ParticipatoryProcess.find_by(organization: organization, slug: PROCESS_SLUG) ||
        created!(Decidim::ParticipatoryProcess.create!(
                   organization: organization, slug: PROCESS_SLUG, published_at: Time.zone.local(2026, 1, 15, 9),
                   title: loc(TITLES[:process]),
                   subtitle: loc("Rozhodnite, na čo obec použije 25 000 eur"),
                   short_description: loc("<p>Obyvatelia navrhujú a vyberajú projekty, ktoré obec zrealizuje z vyhradeného rozpočtu.</p>"),
                   description: loc("<p>Ukážkový proces (fiktívna obec, fiktívne údaje) pre demonštráciu cesty od návrhu obyvateľa " \
                                    "cez rozpočtový projekt a výsledok realizácie až po zmluvu, ktorou bol projekt dodaný.</p>"),
                   start_date: Date.new(2026, 1, 15), end_date: Date.new(2026, 12, 31)
                 ))
    end

    def ensure_step!(space)
      space.steps.find_by(active: true) || space.steps.first ||
        created!(Decidim::ParticipatoryProcessStep.create!(
                   participatory_process: space, active: true,
                   title: loc("Realizácia vybraných projektov"), description: loc("<p>Vybrané projekty sa dodávajú.</p>"),
                   start_date: Date.new(2026, 4, 1), end_date: Date.new(2026, 12, 31)
                 ))
    end

    def ensure_component!(space, manifest_name, name, settings: {}, step_settings: {})
      Decidim::Component.find_by(participatory_space: space, manifest_name: manifest_name.to_s) ||
        created!(Decidim::Component.create!(
                   manifest_name: manifest_name, participatory_space: space, name: loc(name),
                   published_at: Time.zone.local(2026, 1, 15, 9), settings: settings, step_settings: step_settings
                 ))
    end

    def find_by_title(scope, title)
      scope.detect { |record| sk(record.title) == title }
    end

    # Decidim writes the default proposal states (title and the "accepted
    # because" announcement) only in Decidim.default_locale (decidim-proposals
    # 0.31.7 lib/decidim/proposals.rb:89-110), so a Slovak page shows
    # "Accepted". Fill every organization locale from Decidim's own i18n.
    STATE_KEYS = {
      "evaluating" => %w(evaluating proposal_in_evaluation_reason),
      "accepted" => %w(accepted proposal_accepted_reason),
      "rejected" => %w(rejected proposal_rejected_reason)
    }.freeze

    def translate_proposal_states!(component, organization)
      Decidim::Proposals::ProposalState.where(component: component, token: STATE_KEYS.keys).find_each do |state|
        title_key, reason_key = STATE_KEYS.fetch(state.token)
        locales = organization.available_locales.map(&:to_s)
        title = locales.index_with { |l| I18n.with_locale(l) { I18n.t(title_key, scope: "decidim.proposals.answers") } }
        reason = locales.index_with { |l| I18n.with_locale(l) { I18n.t(reason_key, scope: "decidim.proposals.proposals.show") } }
        state.update!(title: state.title.to_h.merge(title), announcement_title: state.announcement_title.to_h.merge(reason))
      end
    end

    def ensure_proposal!(space, resident)
      component = ensure_component!(space, :proposals, "Návrhy obyvateľov")
      Decidim::Proposals.create_default_states!(component, nil, with_traceability: false) unless Decidim::Proposals::ProposalState.exists?(component: component)
      translate_proposal_states!(component, space.organization)

      proposal = find_by_title(Decidim::Proposals::Proposal.where(component: component), TITLES[:proposal])
      return proposal if proposal

      proposal = Decidim::Proposals::Proposal.new(
        component: component, published_at: Time.zone.local(2026, 2, 10, 18),
        title: loc(TITLES[:proposal]),
        body: loc("Pri materskej škole chýba bezpečné ihrisko pre deti od troch do šiestich rokov. Navrhujem nové ihrisko " \
                  "s hernými prvkami (preliezky, hojdačky, pieskovisko) a dopadovým povrchom. Pozemok je obecný."),
        address: "Školská 4, 900 00 Ukážkovo", cost: 25_000,
        cost_report: loc("Herné prvky, dopadový povrch a montáž; odhad podľa cenových ponúk."),
        execution_period: loc("máj až september 2026")
      )
      proposal.coauthorships.build(author: resident)
      proposal.assign_state(:accepted)
      proposal.assign_attributes(
        answer: loc("Návrh bol prijatý. Obec ho zaradila do participatívneho rozpočtu 2026 ako projekt " \
                    "„#{TITLES[:project]}“ a po výbere obyvateľmi ho zrealizuje."),
        answered_at: Time.zone.local(2026, 3, 5, 10), state_published_at: Time.zone.local(2026, 3, 5, 10)
      )
      proposal.save!
      created!(proposal)
    end

    def ensure_project!(space, step, proposal)
      component = ensure_component!(space, :budgets, "Rozpočet",
                                    step_settings: { step.id.to_s => { votes: "finished" } })
      budget = find_by_title(Decidim::Budgets::Budget.where(component: component), TITLES[:budget]) ||
               created!(Decidim::Budgets::Budget.create!(
                          component: component, title: loc(TITLES[:budget]), total_budget: 60_000,
                          description: loc("<p>Rozpočet určený na projekty, o ktorých rozhodli obyvatelia.</p>")
                        ))

      project = find_by_title(Decidim::Budgets::Project.where(budget: budget), TITLES[:project])
      project ||= created!(Decidim::Budgets::Project.create!(
                             budget: budget, title: loc(TITLES[:project]), budget_amount: 25_000,
                             selected_at: Time.zone.local(2026, 4, 2, 12), address: "Školská 4, 900 00 Ukážkovo",
                             description: loc("<p>Nové detské ihrisko pri materskej škole: herné prvky, dopadový povrch a oplotenie. " \
                                              "Projekt vznikol z návrhu obyvateľa a obyvatelia ho vybrali v hlasovaní.</p>")
                           ))

      link_once(project, proposal, "included_proposals")
      project
    end

    def ensure_result!(space, proposal, project)
      component = ensure_component!(space, :accountability, "Plnenie projektov")
      status = Decidim::Accountability::Status.find_by(component: component, key: STATUS_KEY) ||
               created!(Decidim::Accountability::Status.create!(
                          component: component, key: STATUS_KEY, name: loc("Realizované"), progress: 100,
                          description: loc("Projekt je dokončený a odovzdaný do užívania.")
                        ))

      result = find_by_title(Decidim::Accountability::Result.where(component: component), TITLES[:result])
      result ||= created!(Decidim::Accountability::Result.create!(
                            component: component, status: status, progress: 100, title: loc(TITLES[:result]),
                            start_date: Date.new(2026, 5, 4), end_date: Date.new(2026, 9, 18),
                            address: "Školská 4, 900 00 Ukážkovo",
                            description: loc("<p>Ihrisko pri materskej škole je dokončené. Herné prvky dodala firma vybraná " \
                                             "obstarávaním; zmluva je zverejnená v katalógu zmlúv.</p>")
                          ))

      ensure_milestones!(result)
      link_once(result, proposal, "included_proposals")
      link_once(result, project, "included_projects")
      result
    end

    MILESTONES = [
      [Date.new(2026, 5, 4), "Podpis zmluvy s dodávateľom"],
      [Date.new(2026, 8, 24), "Montáž herných prvkov a dopadového povrchu"],
      [Date.new(2026, 9, 18), "Kolaudácia a otvorenie ihriska"]
    ].freeze

    def ensure_milestones!(result)
      MILESTONES.each do |date, title|
        next if result.milestones.any? { |m| m.entry_date == date }

        created! result.milestones.create!(entry_date: date, title: loc(title), description: loc(title))
      end
    end

    # Decidim's own resource link, written only while absent (see class note).
    def link_once(from, to, name)
      return if Decidim::ResourceLink.exists?(from: from, to: to, name: name)

      from.link_resources(from.resource_links_from.where(name: name).map(&:to) + [to], name)
      @created << "link #{from.class.name.demodulize} ##{from.id} -> #{to.class.name.demodulize} ##{to.id} (#{name})"
    end

    def ensure_contract!(editor)
      contract = Decidim::ContractsSk::Contract.find_or_initialize_by(organization: organization, reference: CONTRACT_REFERENCE)
      if contract.new_record?
        contract.assign_attributes(
          title: TITLES[:contract], state: "published", author: editor,
          subject_matter: "Dodávka, doprava a montáž herných prvkov a dopadového povrchu na detské ihrisko pri materskej škole",
          amount: BigDecimal("23600.00"), signed_on: Date.new(2026, 5, 4), effective_from: Date.new(2026, 5, 5),
          crz_url: "https://crz.gov.sk/zmluva/900000110/", source_id: 900_000_110,
          published_at: Time.zone.local(2026, 5, 6, 12), redaction_confirmed_at: Time.zone.local(2026, 5, 6, 11)
        )
        contract.save!
        created!(contract)
      end
      fill_crz_filing!(contract)
      ensure_parties!(contract)
      warn "#{CONTRACT_REFERENCE} is #{contract.state}, not published: the trail will not show it publicly." unless contract.published?
      contract
    end

    # "Zverejnené v CRZ dňa" for the play-equipment contract, so the public
    # detail shows the CRZ provenance. Fills blanks only: a hand-curated record
    # keeps whatever it already has.
    def fill_crz_filing!(contract)
      base = contract.published_at || Time.current
      contract.crz_published_on ||= base.to_date
      contract.crz_filed_at ||= base
      contract.save! if contract.changed?
    end

    # Matched by role alone, like the engine's seed, so a hand-curated supplier
    # name never grows a second party.
    def ensure_parties!(contract)
      { "object" => BUYER, "contractor" => SUPPLIER }.each do |role, attrs|
        next if contract.parties.exists?(role: role)

        contract.parties.create!(role: role, name: attrs[:name], ico: attrs[:ico], address: attrs[:address])
      end
    end

    def ensure_contract_links!(contract, result, project)
      [result, project].each do |target|
        contract.links.find_or_create_by!(target_type: target.class.name, target_id: target.id)
      end
    end
  end
end
