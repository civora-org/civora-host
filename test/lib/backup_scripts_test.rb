# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"
require "fileutils"

# Offline tests for the encrypted off-site backup scripts (civora-org/
# civora-platform#167): retention, the strict guard, the off-site copy order and
# its failure handling (with a fake rclone and curl), .env loading and the
# age round trip when `age` is installed. The scripts run from a temporary copy
# of scripts/ so a developer's real .env and Docker are never touched. The live
# round trip (MinIO, a throwaway stack) is in docs/ops/restore-runbook.md.
class BackupScriptsTest < ActiveSupport::TestCase
  SCRIPTS = Rails.root.join("scripts").freeze
  AGE = system("command -v age >/dev/null 2>&1") && system("command -v age-keygen >/dev/null 2>&1")

  setup do
    @root = Pathname(Dir.mktmpdir("backup-scripts"))
    FileUtils.cp_r(SCRIPTS, @root.join("scripts"))
    @bin = @root.join("fakebin").tap(&:mkpath)
    @calls = @root.join("calls.log")
  end

  teardown { FileUtils.remove_entry(@root) }

  # --- retention -------------------------------------------------------------

  test "expires stamps older than the retention window and keeps the rest" do
    now = Time.utc(2026, 10, 14, 3, 20)
    old = stamp(now - (31 * 86_400))
    edge = stamp(now - (30 * 86_400) - 60)
    recent = stamp(now - (29 * 86_400))
    newest = stamp(now - 300)

    out = expired([old, edge, recent, newest], now)

    assert_equal [old, edge].sort, out
  end

  test "never expires the newest backup, whatever its age" do
    now = Time.utc(2026, 10, 14, 3, 20)
    only = stamp(now - (90 * 86_400))
    older = stamp(now - (120 * 86_400))

    assert_equal [older], expired([older, only], now)
    assert_empty expired([only], now)
  end

  test "ignores names that are not backup stamps" do
    now = Time.utc(2026, 10, 14, 3, 20)
    assert_empty expired(["latest", ".drill-fetch.abc", "20261340T000000Z.bak", ""], now)
  end

  test "the retention window is configurable" do
    now = Time.utc(2026, 10, 14, 3, 20)
    kept = stamp(now - (10 * 86_400))
    newest = stamp(now - 60)

    assert_equal [kept], expired([kept, newest], now, days: 7)
  end

  test "the prune script deletes expired local backups and only those" do
    dest = @root.join("backups").tap(&:mkpath)
    now = Time.now.utc
    old = stamp(now - (45 * 86_400))
    recent = stamp(now - (3 * 86_400))
    newest = stamp(now - 60)
    [old, recent, newest].each { |s| dest.join(s).mkpath }
    dest.join("notes").mkpath

    out, status = run_script("backup_prune.sh", dest.to_s)

    assert status.success?, out
    assert_not dest.join(old).exist?
    assert dest.join(recent).exist?
    assert dest.join(newest).exist?
    assert dest.join("notes").exist?, "directories that are not backups are left alone"
  end

  test "the prune script expires off-site backups through rclone and honors BACKUP_OFFSITE_PRUNE=0" do
    now = Time.now.utc
    old = stamp(now - (45 * 86_400))
    newest = stamp(now - 60)
    fake_rclone(lsf_output: "#{old}/\n#{newest}/\n")
    env = offsite_env

    out, status = run_script("backup_prune.sh", @root.join("backups").to_s, env:)
    assert status.success?, out
    assert_includes calls, "rclone purge offsite:bucket-x/city-a/#{old}"
    assert_not_includes calls, "purge offsite:bucket-x/city-a/#{newest}"

    @calls.write("")
    out, status = run_script("backup_prune.sh", @root.join("backups").to_s, env: env.merge("BACKUP_OFFSITE_PRUNE" => "0"))
    assert status.success?, out
    assert_not_includes calls, "purge"
  end

  # --- strict mode and configuration -----------------------------------------

  test "BACKUP_STRICT refuses a plaintext backup before touching Docker" do
    fake_docker_that_must_not_run

    out, status = run_script("backup.sh", @root.join("backups").to_s, env: { "BACKUP_STRICT" => "1" })

    assert_not status.success?
    assert_match(/refusing a plaintext backup/, out)
    assert_not File.exist?(@calls), "docker was called"
  end

  test "BACKUP_STRICT also refuses a backup that would stay on this machine" do
    fake_docker_that_must_not_run

    out, status = run_script("backup.sh", @root.join("backups").to_s,
                             env: { "BACKUP_STRICT" => "1", "BACKUP_AGE_RECIPIENTS" => "age1examplepublickey" })

    assert_not status.success?
    assert_match(/stays on this machine/, out)
    assert_not File.exist?(@calls)
  end

  test "configuration falls back to .env, strips quotes and keeps the environment on top" do
    @root.join(".env").write(<<~ENV)
      BACKUP_OFFSITE_BUCKET="from-dotenv"
      BACKUP_OFFSITE_PREFIX='city-b'
      BACKUP_RETENTION_DAYS=14
    ENV

    out = sh(<<~SH, env: { "BACKUP_OFFSITE_PREFIX" => "from-env" })
      . scripts/lib/backup_env.sh
      backup_env_load
      echo "$BACKUP_OFFSITE_BUCKET|$BACKUP_OFFSITE_PREFIX|$BACKUP_RETENTION_DAYS"
      backup_remote_base
    SH

    assert_equal ["from-dotenv|from-env|14", "offsite:from-dotenv/from-env"], out.lines.map(&:strip)
  end

  test "retention defaults to 30 days" do
    out = sh(". scripts/lib/backup_env.sh; backup_env_load; echo $BACKUP_RETENTION_DAYS")
    assert_equal "30", out.strip
  end

  # --- off-site copy ---------------------------------------------------------

  test "the off-site copy uploads artifacts first, manifest last, verifies, then pings" do
    dir = finished_backup
    fake_rclone
    fake_curl
    env = offsite_env.merge("PUSHGATEWAY_URL" => "http://push.example:9091")

    out, status = run_script("backup_offsite.sh", dir.to_s, env:)

    assert status.success?, out
    rclone_calls = calls.lines.grep(/\Arclone /)
    copies = rclone_calls.grep(/ copy /)
    assert_equal 2, copies.size
    assert_match(/--exclude manifest\.json/, copies.first)
    assert_match(/--include manifest\.json/, copies.second)
    assert_match(%r{offsite:bucket-x/city-a/#{dir.basename}}, copies.first)
    assert_match(/ check /, rclone_calls.last)
    ping = calls.lines.grep(/\Acurl /).last
    assert_match(%r{push\.example:9091/metrics/job/civora-backup}, ping)
    assert_match(/civora_backup_offsite_last_success_unixtime \d+/, ping)
    assert_not_includes calls, "SECRET-VALUE", "credentials must not appear in command lines"
  end

  test "a failed upload exits non-zero and pushes no off-site ping" do
    dir = finished_backup
    fake_rclone(fail_on: "copy")
    fake_curl

    out, status = run_script("backup_offsite.sh", dir.to_s, env: offsite_env.merge("PUSHGATEWAY_URL" => "http://push.example:9091"))

    assert_not status.success?, out
    assert_not_includes calls, "civora_backup_offsite_last_success_unixtime"
  end

  test "a failed verification exits non-zero and pushes no off-site ping" do
    dir = finished_backup
    fake_rclone(fail_on: "check")
    fake_curl

    out, status = run_script("backup_offsite.sh", dir.to_s, env: offsite_env.merge("PUSHGATEWAY_URL" => "http://push.example:9091"))

    assert_not status.success?, out
    assert_not_includes calls, "civora_backup_offsite_last_success_unixtime"
  end

  test "strict mode refuses to upload a plaintext backup" do
    dir = finished_backup(encrypted: false)
    fake_rclone

    out, status = run_script("backup_offsite.sh", dir.to_s, env: offsite_env.merge("BACKUP_STRICT" => "1"))

    assert_not status.success?
    assert_match(/not encrypted/, out)
    assert_not_includes calls, "rclone"
  end

  test "an incomplete backup directory is not uploaded" do
    dir = @root.join("backups", "20261014T031500Z").tap(&:mkpath)
    fake_rclone

    _out, status = run_script("backup_offsite.sh", dir.to_s, env: offsite_env)

    assert_not status.success?
    assert_not_includes calls, "rclone"
  end

  # --- fetch -----------------------------------------------------------------

  test "latest picks the newest remote backup that has a manifest" do
    fake_rclone(lsf_output: "20261012T031500Z/manifest.json\n20261013T031500Z/db.dump.age\n20261013T031500Z/manifest.json\n" \
                            "20261014T031500Z/db.dump.age\n", copy_creates: true)

    out, status = run_script("backup_fetch.sh", "latest", @root.join("fetched").to_s, env: offsite_env)

    assert_not status.success?, "20261014 has no manifest and 20261013 has no sha256 in the fake, so the fetch must stop"
    assert_includes calls, "offsite:bucket-x/city-a/20261013T031500Z"
    assert_not_includes calls, "20261014T031500Z "
    assert_match(/Incomplete backup/, out)
  end

  # --- age round trip --------------------------------------------------------

  test "an encrypted artifact decrypts with the private key and not with another" do
    skip "age is not installed" unless AGE

    key = @root.join("key.txt")
    other = @root.join("other.txt")
    system("age-keygen -o #{key} >/dev/null 2>&1")
    system("age-keygen -o #{other} >/dev/null 2>&1")
    recipient = `age-keygen -y #{key}`.strip
    backup = @root.join("backups", "20261014T031500Z").tap(&:mkpath)
    payload = "fictional database dump #{SecureRandom.hex(8)}"

    sh(". scripts/lib/backup_env.sh; printf %s \"$PAYLOAD\" | backup_age_encrypt > #{backup}/db.dump.age; " \
       "printf %s tar > /dev/null; printf %s \"$PAYLOAD\" | backup_age_encrypt > #{backup}/storage.tar.gz.age",
       env: { "BACKUP_AGE_RECIPIENTS" => recipient, "PAYLOAD" => payload })
    Dir.chdir(backup) { system("shasum -a 256 db.dump.age storage.tar.gz.age > sha256.txt") }

    assert_not_includes backup.join("db.dump.age").binread, payload
    out, status = run_script("backup_decrypt.sh", backup.to_s, @root.join("plain").to_s,
                             env: { "BACKUP_AGE_IDENTITY_FILE" => key.to_s })
    assert status.success?, out
    assert_equal payload, @root.join("plain/db.dump").read

    out, status = run_script("backup_decrypt.sh", backup.to_s, @root.join("plain2").to_s,
                             env: { "BACKUP_AGE_IDENTITY_FILE" => other.to_s })
    assert_not status.success?, out
  end

  test "a tampered encrypted artifact is rejected by the checksum before any decryption" do
    skip "age is not installed" unless AGE

    key = @root.join("key.txt")
    system("age-keygen -o #{key} >/dev/null 2>&1")
    backup = finished_backup
    File.write(backup.join("db.dump.age"), "tampered", mode: "a")

    out, status = run_script("backup_decrypt.sh", backup.to_s, @root.join("plain").to_s,
                             env: { "BACKUP_AGE_IDENTITY_FILE" => key.to_s })

    assert_not status.success?, out
    assert_not @root.join("plain/db.dump").exist?
  end

  # --- documentation drift ---------------------------------------------------

  test "every BACKUP_ variable the scripts read is documented in .env.example and the runbook" do
    names = SCRIPTS.join("lib/backup_env.sh").read.scan(/BACKUP_[A-Z_]+/).uniq - ["BACKUP_RCLONE_LOCAL"]
    example = Rails.root.join(".env.example").read
    runbook = Rails.root.join("docs/ops/restore-runbook.md").read
    names.each do |name|
      assert_includes example, name, "#{name} missing from .env.example"
      assert_includes runbook, name, "#{name} missing from docs/ops/restore-runbook.md"
    end
  end

  private

  def stamp(time) = time.utc.strftime("%Y%m%dT%H%M%SZ")

  def expired(stamps, now, days: nil)
    env = { "BACKUP_NOW_EPOCH" => now.to_i.to_s }
    env["BACKUP_RETENTION_DAYS"] = days.to_s if days
    out = sh(". scripts/lib/backup_retention.sh; backup_expired_stamps", env:, stdin: stamps.join("\n"))
    out.lines.map(&:strip).reject(&:empty?)
  end

  def sh(script, env: {}, stdin: "")
    out, status = Open3.capture2e(base_env.merge(env), "sh", "-c", script, chdir: @root.to_s, stdin_data: stdin)
    assert status.success?, out
    out
  end

  def run_script(name, *, env: {})
    Open3.capture2e(base_env.merge(env), @root.join("scripts", name).to_s, *, chdir: @root.to_s)
  end

  def base_env
    {
      "PATH" => "#{@bin}:#{ENV.fetch("PATH")}",
      "CALLS" => @calls.to_s,
      "BACKUP_AGE_RECIPIENTS" => nil, "BACKUP_STRICT" => nil, "BACKUP_OFFSITE_BUCKET" => nil,
      "BACKUP_OFFSITE_PRUNE" => nil, "BACKUP_RETENTION_DAYS" => nil, "PUSHGATEWAY_URL" => nil
    }
  end

  def offsite_env
    {
      "BACKUP_OFFSITE_BUCKET" => "bucket-x", "BACKUP_OFFSITE_PREFIX" => "city-a",
      "BACKUP_OFFSITE_ACCESS_KEY_ID" => "test-access-key", "BACKUP_OFFSITE_SECRET_ACCESS_KEY" => "SECRET-VALUE"
    }
  end

  def calls = @calls.exist? ? @calls.read : ""

  def finished_backup(encrypted: true)
    dir = @root.join("backups", "20261014T031500Z").tap(&:mkpath)
    names = encrypted ? %w(db.dump.age storage.tar.gz.age) : %w(db.dump storage.tar.gz)
    names.each { |n| dir.join(n).write("age-encryption.org/v1\nfictional") }
    dir.join("manifest.json").write("{}")
    dir.join("sha256.txt").write("")
    dir
  end

  # Fake rclone: logs "rclone <args>", answers lsf, can fail on a subcommand.
  def fake_rclone(lsf_output: "", fail_on: nil, copy_creates: false)
    write_bin("rclone", <<~SH)
      #!/bin/sh
      echo "rclone $*" >> "$CALLS"
      for a in "$@"; do [ "$a" = "#{fail_on}" ] && [ -n "#{fail_on}" ] && exit 1; done
      case "$1" in
        lsf) printf '%s' '#{lsf_output}' ;;
        copy) #{copy_creates ? 'mkdir -p "$3"; echo "{}" > "$3/manifest.json"' : ":"} ;;
      esac
      exit 0
    SH
  end

  def fake_curl
    write_bin("curl", <<~SH)
      #!/bin/sh
      echo "curl $* $(cat)" >> "$CALLS"
      exit 0
    SH
  end

  def fake_docker_that_must_not_run
    write_bin("docker", "#!/bin/sh\necho \"docker $*\" >> \"$CALLS\"\nexit 0\n")
  end

  def write_bin(name, body)
    path = @bin.join(name)
    path.write(body)
    path.chmod(0o755)
  end
end
