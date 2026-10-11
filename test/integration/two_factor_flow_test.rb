# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "support/two_factor_helpers"

# civora-org/civora-platform#164 (ADR-010): admins and engine role holders pass
# a TOTP challenge before any admin surface; participants are unaffected.
class TwoFactorFlowTest < ActionDispatch::IntegrationTest
  include TwoFactorHelpers
  include Warden::Test::Helpers

  setup do
    @organization = build_organization
    @admin = create_admin(@organization)
    host! @organization.host
    stub_webpack_manifest
  end

  teardown do
    Warden.test_reset!
    unstub_webpack_manifest
  end

  # -- enrolment gate ---------------------------------------------------------

  test "an unenrolled admin is sent to enrol from every admin path" do
    sign_in_with_password(@admin)

    ["/admin", "/contracts/admin", "/contracts/admin/contracts"].each do |path|
      get path

      assert_redirected_to "/two_factor/enrolment", path
    end
  end

  test "password sign-in of an unenrolled admin lands on enrolment" do
    sign_in_with_password(@admin)

    assert_redirected_to "/two_factor/enrolment"
  end

  test "the enrolment page shows a QR code, the key and a code field, and stores nothing readable" do
    sign_in_with_password(@admin)
    get "/two_factor/enrolment"

    assert_response :ok
    assert_select "svg.two-factor__qr[role=img] path[d^=M]"
    assert_select "input[name=?][autocomplete=?]", "two_factor[code]", "one-time-code"
    credential = TwoFactor::Credential.find_by!(decidim_user_id: @admin.id)

    assert_not credential.confirmed?
    assert_not_includes response.body, credential.otp_secret, "raw seed must not appear unspaced"
    assert_includes response.body.delete(" "), credential.otp_secret
  end

  test "the pending seed is stable across page loads" do
    sign_in_with_password(@admin)
    get "/two_factor/enrolment"
    first = TwoFactor::Credential.find_by!(decidim_user_id: @admin.id).otp_secret
    get "/two_factor/enrolment"

    assert_equal first, TwoFactor::Credential.find_by!(decidim_user_id: @admin.id).otp_secret
  end

  test "a wrong code does not enrol" do
    sign_in_with_password(@admin)
    get "/two_factor/enrolment"
    post "/two_factor/enrolment", params: { two_factor: { code: "000000" } }

    assert_response :unprocessable_entity
    assert_not TwoFactor::Credential.find_by!(decidim_user_id: @admin.id).confirmed?
    get "/admin"

    assert_redirected_to "/two_factor/enrolment"
  end

  test "a correct code enrols, shows ten recovery codes once, and opens the admin" do
    sign_in_with_password(@admin)
    get "/two_factor/enrolment"
    credential = TwoFactor::Credential.find_by!(decidim_user_id: @admin.id)
    post "/two_factor/enrolment", params: { two_factor: { code: current_code(credential) } }

    assert_response :ok
    assert_select "ul.two-factor__codes li", 10
    assert_predicate credential.reload, :confirmed?
    assert_equal ["enrolled"], TwoFactor::Event.where(decidim_user_id: @admin.id).pluck(:kind)

    get "/admin"

    assert_response :ok
  end

  test "an enrolled user cannot re-enrol with the password alone" do
    credential = enrol!(@admin)
    old_secret = credential.otp_secret
    sign_in_with_password(@admin)
    get "/two_factor/enrolment"

    assert_redirected_to "/two_factor/challenge"
    post "/two_factor/enrolment", params: { two_factor: { code: "123456" } }

    assert_redirected_to "/two_factor/challenge"
    assert_equal old_secret, credential.reload.otp_secret
  end

  # -- verify on login --------------------------------------------------------

  test "an enrolled admin is challenged after the password, and locked out of the admin until verified" do
    credential = enrol!(@admin)
    sign_in_with_password(@admin)

    assert_redirected_to "/two_factor/challenge"
    get "/admin"

    assert_redirected_to "/two_factor/challenge"
    get "/contracts/admin"

    assert_redirected_to "/two_factor/challenge"

    post "/two_factor/challenge", params: { two_factor: { code: current_code(credential) } }

    assert_response :redirect
    get "/admin"

    assert_response :ok
    get "/contracts/admin"

    assert_response :ok
  end

  test "the challenge sends the user back to where they were going" do
    credential = enrol!(@admin)
    sign_in_with_password(@admin)
    get "/contracts/admin/contracts"
    post "/two_factor/challenge", params: { two_factor: { code: current_code(credential) } }

    assert_redirected_to "/contracts/admin/contracts"
  end

  test "a wrong code is rejected with a generic message and does not open the admin" do
    enrol!(@admin)
    sign_in_with_password(@admin)
    post "/two_factor/challenge", params: { two_factor: { code: "000000" } }

    assert_response :unprocessable_entity
    get "/admin"

    assert_redirected_to "/two_factor/challenge"
  end

  test "a used code cannot be replayed in a new sign-in" do
    credential = enrol!(@admin)
    code = current_code(credential)
    sign_in_with_password(@admin)
    post "/two_factor/challenge", params: { two_factor: { code: } }
    delete "/users/sign_out"

    sign_in_with_password(@admin)
    post "/two_factor/challenge", params: { two_factor: { code: } }

    assert_response :unprocessable_entity
  end

  test "a fresh sign-in starts unverified even in the same browser session" do
    credential = enrol!(@admin)
    sign_in_with_password(@admin)
    post "/two_factor/challenge", params: { two_factor: { code: current_code(credential) } }
    delete "/users/sign_out"
    sign_in_with_password(@admin)
    get "/admin"

    assert_redirected_to "/two_factor/challenge"
  end

  test "any new authentication event in a live session clears the verified flag" do
    credential = enrol!(@admin)
    sign_in_with_password(@admin)
    post "/two_factor/challenge", params: { two_factor: { code: current_code(credential) } }
    get "/admin"

    assert_response :ok

    login_as(@admin, scope: :user) # a second Warden set_user, e.g. a remember-me or omniauth sign-in
    get "/admin"

    assert_redirected_to "/two_factor/challenge"
  end

  test "five wrong codes lock the challenge with 429, even for the right code" do
    credential = enrol!(@admin)
    sign_in_with_password(@admin)
    5.times { post "/two_factor/challenge", params: { two_factor: { code: "000000" } } }

    assert_response :too_many_requests
    post "/two_factor/challenge", params: { two_factor: { code: current_code(credential) } }

    assert_response :too_many_requests
  end

  test "a recovery code works once, then is refused" do
    credential = enrol!(@admin)
    code = TwoFactor::RecoveryCode.generate_for!(credential).first
    sign_in_with_password(@admin)
    post "/two_factor/challenge", params: { two_factor: { code: } }

    assert_response :redirect
    assert_includes flash[:notice], "9"
    assert_includes TwoFactor::Event.where(decidim_user_id: @admin.id).pluck(:kind), "recovery_used"
    get "/admin"

    assert_response :ok

    delete "/users/sign_out"
    sign_in_with_password(@admin)
    post "/two_factor/challenge", params: { two_factor: { code: } }

    assert_response :unprocessable_entity
  end

  test "recovery codes can be regenerated only from a verified session" do
    credential = enrol!(@admin)
    TwoFactor::RecoveryCode.generate_for!(credential)
    sign_in_with_password(@admin)
    post "/two_factor/recovery_codes"

    assert_redirected_to "/two_factor/challenge"

    post "/two_factor/challenge", params: { two_factor: { code: current_code(credential) } }
    get "/two_factor/recovery_codes"

    assert_response :ok
    post "/two_factor/recovery_codes"

    assert_response :ok
    assert_select "ul.two-factor__codes li", 10
    assert_includes TwoFactor::Event.pluck(:kind), "recovery_regenerated"
  end

  # -- scope ------------------------------------------------------------------

  test "a participant is unaffected and the second-factor pages bounce them home" do
    participant = create_participant(@organization)
    sign_in_with_password(participant)

    assert_not_equal "/two_factor/challenge", URI(response.location).path
    get "/two_factor/enrolment"

    assert_redirected_to "/"
    get "/"

    assert_response :ok
    get "/contracts"

    assert_response :ok
  end

  test "the public catalogue never asks an unverified admin for a code" do
    enrol!(@admin)
    sign_in_with_password(@admin)
    get "/contracts"

    assert_response :ok
  end

  test "an engine role holder who is not an admin must also use a second factor" do
    holder = create_participant(@organization)
    resolver = ->(user, _context) { user.id == holder.id ? [:editor] : [] }
    sign_in_with_password(holder)

    Decidim::ContractsSk.stub(:role_resolver, -> { resolver }) do
      assert TwoFactor::Policy.required?(holder)
      assert_not TwoFactor::Policy.required?(create_participant(@organization))
      get "/contracts/admin"

      assert_redirected_to "/two_factor/enrolment"
    end
  end

  test "remember-me is withheld from users who need a second factor" do
    participant = create_participant(@organization)
    @admin.remember_me = true
    participant.remember_me = true

    assert_nil @admin.remember_me
    assert participant.remember_me
  end

  # -- engine seam ------------------------------------------------------------

  test "the engine seams are wired to the host" do
    credential = enrol!(@admin)
    session = {}

    assert_not Decidim::ContractsSk.second_factor_satisfied.call(@admin, session)
    TwoFactor::Policy.mark_verified!(session, @admin)

    assert Decidim::ContractsSk.second_factor_satisfied.call(@admin, session)
    assert Decidim::ContractsSk.second_factor_satisfied.call(create_participant(@organization), {})
    assert_predicate credential, :confirmed?
  end

  test "a verified flag for another user does not satisfy the seam" do
    enrol!(@admin)

    assert_not Decidim::ContractsSk.second_factor_satisfied.call(@admin, { TwoFactor::Policy::SESSION_KEY => @admin.id + 1 })
  end

  # -- throttle ---------------------------------------------------------------

  test "Rack::Attack throttles the code step per IP" do
    original = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    enrol!(@admin)
    sign_in_with_password(@admin)

    11.times { post "/two_factor/challenge", params: { two_factor: { code: "000000" } } }

    assert_response :too_many_requests
    assert_equal "Retry later\n", response.body
  ensure
    Rack::Attack.cache.store = original
  end

  # -- operator reset ---------------------------------------------------------

  test "operator reset removes the factor, ends sessions, audits, and forces re-enrolment" do
    credential = enrol!(@admin)
    TwoFactor::RecoveryCode.generate_for!(credential)
    sign_in_with_password(@admin)
    post "/two_factor/challenge", params: { two_factor: { code: current_code(credential) } }
    get "/admin"

    assert_response :ok

    TwoFactor::Reset.call(email: @admin.email.upcase, reason: "Lost phone, identity checked by phone (ticket 12)")

    assert_nil TwoFactor::Credential.find_by(decidim_user_id: @admin.id)
    assert_equal 0, TwoFactor::RecoveryCode.count
    event = TwoFactor::Event.find_by!(decidim_user_id: @admin.id, kind: "reset")

    assert_equal "operator", event.actor
    assert_includes event.reason, "ticket 12"

    get "/admin"

    assert_redirected_to "/users/sign_in"
    sign_in_with_password(@admin)

    assert_redirected_to "/two_factor/enrolment"
  end

  test "operator reset needs a reason and an enrolled user" do
    assert_raises(TwoFactor::Reset::Error) { TwoFactor::Reset.call(email: @admin.email, reason: " ") }
    assert_raises(TwoFactor::Reset::Error) { TwoFactor::Reset.call(email: @admin.email, reason: "x") }
    assert_raises(TwoFactor::Reset::Error) { TwoFactor::Reset.call(email: "nobody@example.org", reason: "x") }
  end

  test "reset_all clears every credential, audits each, and needs a reason" do
    enrol!(@admin)
    enrol!(create_admin(@organization))

    assert_raises(TwoFactor::Reset::Error) { TwoFactor::Reset.all(reason: "") }
    assert_equal 2, TwoFactor::Reset.all(reason: "secret_key_base rotated")
    assert_equal 0, TwoFactor::Credential.count
    assert_equal 2, TwoFactor::Event.where(kind: "reset").count
  end

  test "rollout status lists required users and their enrolment" do
    enrolled = create_admin(@organization)
    enrol!(enrolled)
    create_participant(@organization)
    rows = TwoFactor::Reset.status_rows.index_by { |row| row[:id] }

    assert rows[enrolled.id][:enrolled]
    assert_not rows[@admin.id][:enrolled]
    assert_equal 2, rows.size
  end
end
