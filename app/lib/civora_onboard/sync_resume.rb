# frozen_string_literal: true

require "cgi"
require "open3"
require "time"
require "uri"

module CivoraOnboard
  # Runs the first CRZ sync for an organization and resumes it when the
  # ekosystem datahub rate limit (60 requests a minute, HTTP 429) stops the
  # engine early: the stop message names the URL it gave up on, whose
  # `since=` is where the next pass continues, after waiting for the rate
  # window. Bounded (max passes, max passes without progress). Output is
  # whatever the engine's rake task prints: ids and counts only, no payloads.
  class SyncResume
    STOP_MARKER = "sync stopped early"
    DEFAULT_WAIT = 65
    DEFAULT_MAX_PASSES = 40
    DEFAULT_MAX_STALLS = 3

    Pass = Struct.new(:since, :success, :output, keyword_init: true)
    Outcome = Struct.new(:status, :passes, :last_since, keyword_init: true) do
      def complete? = status == :complete
    end

    # since_for_resume("... gave up on https://x/sync?since=2026-01-02T03%3A04%3A05Z&last_id=9 after 6 attempts")
    # => "2026-01-02T03:04:05Z"; nil when the message carries no usable since.
    def self.resume_since(output)
      line = output.to_s.lines.reverse.find { |l| l.include?(STOP_MARKER) }
      return unless line

      raw = line[/[?&]since=([^&\s]+)/, 1]
      return unless raw

      value = CGI.unescape(raw)
      Time.iso8601(value)
      value
    rescue ArgumentError
      nil
    end

    # runner:  ->(organization_id, since) { Pass } (default: the engine rake task in a subprocess)
    # sleeper: ->(seconds) {}  (injected in tests)
    # log:     ->(line) {}
    # options: wait:, max_passes:, max_stalls:, sleeper:, log:
    def initialize(organization_id:, since:, runner: nil, **limits)
      @organization_id = organization_id
      @since = since
      @runner = runner || method(:run_rake_task)
      @sleeper = limits.fetch(:sleeper) { ->(seconds) { sleep(seconds) } }
      @log = limits.fetch(:log) { ->(line) { $stdout.puts(line) } }
      @wait = limits.fetch(:wait, DEFAULT_WAIT)
      @max_passes = limits.fetch(:max_passes, DEFAULT_MAX_PASSES)
      @max_stalls = limits.fetch(:max_stalls, DEFAULT_MAX_STALLS)
    end

    def call
      Time.iso8601(@since)
      since = @since
      stalls = 0
      passes = 0

      @max_passes.times do
        passes += 1
        @log.call("[onboard] pass #{passes}/#{@max_passes}: sync organization ##{@organization_id} since #{since}")
        pass = @runner.call(@organization_id, since)
        @log.call(pass.output.to_s.rstrip) if pass.output.to_s.strip.present?

        return Outcome.new(status: :complete, passes: passes, last_since: since) if pass.success
        return Outcome.new(status: :failed, passes: passes, last_since: since) unless pass.output.to_s.include?(STOP_MARKER)

        next_since = self.class.resume_since(pass.output)
        return Outcome.new(status: :failed, passes: passes, last_since: since) unless next_since

        # Never move backwards; an unchanged since means no progress this pass.
        advanced = Time.iso8601(next_since) > Time.iso8601(since)
        stalls = advanced ? 0 : stalls + 1
        return Outcome.new(status: :stalled, passes: passes, last_since: since) if stalls >= @max_stalls

        since = next_since if advanced
        @log.call("[onboard] rate-limited; waiting #{@wait}s, resuming since #{since}")
        @sleeper.call(@wait)
      end

      Outcome.new(status: :max_passes, passes: passes, last_since: since)
    end

    private

    def run_rake_task(organization_id, since)
      output, status = Open3.capture2e(
        { "DISABLE_SPRING" => "1" },
        Rails.root.join("bin/rails").to_s,
        "decidim_contracts_sk:crz_import:sync[#{organization_id},#{since}]"
      )
      Pass.new(since: since, success: status.success?, output: output)
    end
  end
end
