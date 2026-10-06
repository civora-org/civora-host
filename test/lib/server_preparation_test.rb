# frozen_string_literal: true

require "test_helper"
require "rake"
require "capybara" # Decidim's URL resolver reads Capybara.server_port
require "factory_bot"
require "decidim/core/test/factories"

# Public demo server tooling (docs/ops/demo-server.md): the organization
# preparation, the rake task's DEMO_MODE guard and the mail-sink initializer.
class ServerPreparationTest < ActiveSupport::TestCase
  PASSWORD = "Sample-Pass-9f3k2lq8x7zv"

  setup do
    @organization = FactoryBot.create(:organization, available_locales: %w(en sk), default_locale: "en")
  end

  test "sets the Slovak locale and the visible demo banner" do
    CivoraDemo::ServerPreparation.call(@organization, admin_email: nil, admin_password: nil)
    @organization.reload

    assert_equal "sk", @organization.default_locale
    assert @organization.enable_omnipresent_banner
    assert_equal "DEMO — fiktívne údaje", @organization.omnipresent_banner_title["sk"]
    assert_equal "/contracts", @organization.omnipresent_banner_url
  end

  test "creates a confirmed admin who accepted the admin terms" do
    CivoraDemo::ServerPreparation.call(@organization, admin_email: "Demo-Admin@Example.org", admin_password: PASSWORD)

    admin = Decidim::User.find_by!(organization: @organization, email: "demo-admin@example.org")
    assert admin.admin?
    assert admin.confirmed?
    assert admin.admin_terms_accepted_at.present?
    assert admin.valid_password?(PASSWORD)
  end

  test "is idempotent and keeps the password when none is passed again" do
    2.times { CivoraDemo::ServerPreparation.call(@organization, admin_email: "demo-admin@example.org", admin_password: PASSWORD) }
    CivoraDemo::ServerPreparation.call(@organization, admin_email: "demo-admin@example.org", admin_password: "")

    assert_equal 1, Decidim::User.where(organization: @organization, email: "demo-admin@example.org").count
    assert Decidim::User.find_by!(email: "demo-admin@example.org").valid_password?(PASSWORD)
  end

  test "refuses to create a new admin without a password" do
    assert_raises(ArgumentError) do
      CivoraDemo::ServerPreparation.call(@organization, admin_email: "demo-admin@example.org", admin_password: nil)
    end
    assert_not Decidim::User.exists?(email: "demo-admin@example.org")
  end

  test "the rake task aborts without DEMO_MODE=1 and changes nothing" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("civora:demo:prepare_server")
    task = Rake::Task["civora:demo:prepare_server"]
    task.reenable

    with_env("DEMO_MODE" => nil) do
      assert_raises(SystemExit) { capture_io { task.invoke(@organization.id.to_s) } }
    end
    assert_not @organization.reload.enable_omnipresent_banner
  end

  test "with DEMO_MODE=1 the mailer writes files instead of delivering" do
    initializer = Rails.root.join("config/initializers/demo_mode.rb").to_s
    previous = [ActionMailer::Base.delivery_method, ActionMailer::Base.file_settings]
    with_env("DEMO_MODE" => "1") { load initializer }

    assert_equal :file, ActionMailer::Base.delivery_method
    assert_equal Rails.root.join("tmp/demo-mails").to_s, ActionMailer::Base.file_settings[:location]
  ensure
    ActionMailer::Base.delivery_method, ActionMailer::Base.file_settings = previous
  end

  test "without DEMO_MODE the initializer leaves the delivery method alone" do
    before = ActionMailer::Base.delivery_method
    with_env("DEMO_MODE" => nil) { load Rails.root.join("config/initializers/demo_mode.rb").to_s }

    assert_equal before, ActionMailer::Base.delivery_method
  end

  private

  def with_env(vars)
    old = vars.keys.index_with { |k| ENV.fetch(k, nil) }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
