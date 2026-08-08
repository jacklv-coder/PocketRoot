#!/usr/bin/env ruby

require "json"
require "net/http"
require "optparse"
require "time"
require "uri"

module PocketRootPRCIReuse
  Decision = Struct.new(:reusable, :reason, keyword_init: true)

  class GitHubAPI
    def initialize(base_url:, token:)
      @base_url = base_url.end_with?("/") ? base_url : "#{base_url}/"
      @token = token
    end

    def get(path, query = {})
      uri = URI.join(@base_url, path.sub(%r{\A/+}, ""))
      uri.query = URI.encode_www_form(query) unless query.empty?
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["Authorization"] = "Bearer #{@token}"
      request["X-GitHub-Api-Version"] = "2022-11-28"
      response = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 10,
        read_timeout: 20
      ) { |http| http.request(request) }
      unless response.is_a?(Net::HTTPSuccess)
        raise "GitHub API returned HTTP #{response.code} for #{uri.path}"
      end

      JSON.parse(response.body)
    end
  end

  class Verifier
    WORKFLOW_NAME = "CI"
    WORKFLOW_PATH = ".github/workflows/ci.yml"
    TRUST_BOUNDARY_PATHS = [
      WORKFLOW_PATH,
      "Scripts/verify-pr-ci-reuse.rb"
    ].freeze
    REQUIRED_JOBS = [
      "Classify changes",
      "Test and build",
      "Minimum Xcode 16.0 / Native runtime",
      "Minimum Xcode 16.0 / UI (External consumer)",
      "Minimum Xcode 16.0 / UI (Quick Start iPhone)",
      "Minimum Xcode 16.0 / UI (Host App iPhone)"
    ].freeze

    def initialize(api:)
      @api = api
    end

    def verify(repository:, commit_sha:, base_ref:)
      return reject("invalid_repository") unless valid_repository?(repository)
      return reject("invalid_commit_sha") unless commit_sha.match?(/\A[0-9a-f]{40}\z/)
      return reject("invalid_base_ref") if base_ref.empty?

      pull_requests = @api.get(
        "/repos/#{repository}/commits/#{commit_sha}/pulls",
        "per_page" => "100"
      )
      return reject("merged_pr_page_not_unique") if pull_requests.length >= 100

      matching = pull_requests.select do |pull_request|
        pull_request["merge_commit_sha"] == commit_sha &&
          !pull_request["merged_at"].nil? &&
          pull_request.dig("base", "ref") == base_ref &&
          pull_request.dig("base", "repo", "full_name") == repository
      end
      return reject("merged_pr_not_unique") unless matching.length == 1

      pull_request = matching.first
      changed_files = @api.get(
        "/repos/#{repository}/pulls/#{pull_request["number"]}/files",
        "per_page" => "100"
      )
      if changed_files.length >= 100 || changed_files.any? { |file| trust_boundary?(file["filename"]) }
        return reject("ci_trust_boundary_changed")
      end

      head_sha = pull_request.dig("head", "sha")
      head_ref = pull_request.dig("head", "ref")
      head_repository = pull_request.dig("head", "repo", "full_name")
      base_sha = pull_request.dig("base", "sha")
      merged_at = parse_time(pull_request["merged_at"])
      unless head_sha&.match?(/\A[0-9a-f]{40}\z/) &&
             !head_ref.to_s.empty? &&
             valid_repository?(head_repository.to_s) &&
             base_sha&.match?(/\A[0-9a-f]{40}\z/) &&
             merged_at
        return reject("invalid_pr_metadata")
      end

      commit = @api.get("/repos/#{repository}/commits/#{commit_sha}")
      parents = commit.fetch("parents", [])
      merge_tree = commit.dig("commit", "tree", "sha")
      unless commit["sha"] == commit_sha &&
             commit_sha != head_sha &&
             parents.length == 1 &&
             parents.first["sha"] == base_sha &&
             merge_tree&.match?(/\A[0-9a-f]{40}\z/)
        return reject("unsupported_merge_shape")
      end

      head_commit = @api.get("/repos/#{repository}/commits/#{head_sha}")
      unless head_commit["sha"] == head_sha &&
             head_commit.dig("commit", "tree", "sha") == merge_tree
        return reject("merged_tree_not_tested")
      end

      head_pull_requests = @api.get(
        "/repos/#{repository}/commits/#{head_sha}/pulls",
        "per_page" => "100"
      )
      if head_pull_requests.length != 1 ||
         !same_pull_request?(head_pull_requests.first, pull_request)
        return reject("head_pr_not_unique")
      end

      runs_response = @api.get(
        "/repos/#{repository}/actions/runs",
        "event" => "pull_request",
        "head_sha" => head_sha,
        "status" => "completed",
        "per_page" => "100"
      )
      workflow_runs = runs_response.fetch("workflow_runs", [])
      total_runs = runs_response["total_count"]
      if !total_runs.is_a?(Integer) || total_runs > workflow_runs.length
        return reject("incomplete_workflow_run_page")
      end
      candidates = workflow_runs.select do |run|
        run["name"] == WORKFLOW_NAME &&
          run["path"] == WORKFLOW_PATH &&
          run["event"] == "pull_request" &&
          run["head_sha"] == head_sha &&
          run["head_branch"] == head_ref &&
          run.dig("head_repository", "full_name") == head_repository &&
          run["conclusion"] == "success" &&
          (updated_at = parse_time(run["updated_at"])) &&
          updated_at <= merged_at
      end
      return reject("successful_pr_ci_not_found") if candidates.empty?

      run_id = candidates.max_by { |run| parse_time(run["updated_at"]) }["id"]
      return reject("invalid_workflow_run") unless run_id.is_a?(Integer)

      jobs_response = @api.get(
        "/repos/#{repository}/actions/runs/#{run_id}/jobs",
        "filter" => "latest",
        "per_page" => "100"
      )
      jobs = jobs_response.fetch("jobs", [])
      total_count = jobs_response["total_count"]
      unless total_count.is_a?(Integer) && total_count == jobs.length
        return reject("incomplete_job_page")
      end

      missing = REQUIRED_JOBS.reject do |name|
        matching_jobs = jobs.select { |job| job["name"] == name }
        matching_jobs.length == 1 && matching_jobs.first["conclusion"] == "success"
      end
      return reject("required_jobs_not_successful") unless missing.empty?

      Decision.new(reusable: true, reason: "verified_pr_ci")
    end

    private

    def reject(reason)
      Decision.new(reusable: false, reason: reason)
    end

    def valid_repository?(repository)
      repository.match?(%r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z})
    end

    def trust_boundary?(path)
      TRUST_BOUNDARY_PATHS.include?(path) || path.to_s.start_with?(".github/actions/")
    end

    def same_pull_request?(candidate, expected)
      candidate["number"] == expected["number"] &&
        candidate["merge_commit_sha"] == expected["merge_commit_sha"] &&
        candidate.dig("base", "ref") == expected.dig("base", "ref") &&
        candidate.dig("base", "repo", "full_name") ==
          expected.dig("base", "repo", "full_name") &&
        candidate.dig("head", "sha") == expected.dig("head", "sha") &&
        candidate.dig("head", "ref") == expected.dig("head", "ref") &&
        candidate.dig("head", "repo", "full_name") ==
          expected.dig("head", "repo", "full_name")
    end

    def parse_time(value)
      Time.iso8601(value)
    rescue ArgumentError, TypeError
      nil
    end
  end

  class CLI
    def self.run(arguments, environment: ENV)
      options = {
        api_url: environment.fetch("GITHUB_API_URL", "https://api.github.com")
      }
      parser = OptionParser.new do |spec|
        spec.on("--repository OWNER/REPO") { |value| options[:repository] = value }
        spec.on("--commit SHA") { |value| options[:commit_sha] = value }
        spec.on("--base-ref REF") { |value| options[:base_ref] = value }
        spec.on("--output PATH") { |value| options[:output] = value }
      end
      parser.parse!(arguments)
      required = %i[repository commit_sha base_ref output]
      unless required.all? { |key| options[key] && !options[key].empty? }
        warn parser
        return 2
      end

      token = environment["GITHUB_TOKEN"]
      decision = if token.nil? || token.empty?
        Decision.new(reusable: false, reason: "missing_github_token")
      else
        begin
          api = GitHubAPI.new(base_url: options[:api_url], token: token)
          Verifier.new(api: api).verify(
            repository: options[:repository],
            commit_sha: options[:commit_sha],
            base_ref: options[:base_ref]
          )
        rescue StandardError => error
          warn "PR CI reuse verification failed closed: #{error.class}: #{error.message}"
          Decision.new(reusable: false, reason: "github_api_error")
        end
      end

      File.open(options[:output], "a") do |output|
        output.puts "reused_pr_ci=#{decision.reusable}"
        output.puts "reuse_reason=#{decision.reason}"
      end
      warn "PR CI reuse: #{decision.reusable} (#{decision.reason})"
      0
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit PocketRootPRCIReuse::CLI.run(ARGV)
end
