require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../../Scripts/verify-pr-ci-reuse"

class PRCIReuseTests < Minitest::Test
  REPOSITORY = "jacklv-coder/PocketRoot"
  MERGE_SHA = "a" * 40
  HEAD_SHA = "b" * 40
  MERGED_AT = "2026-08-08T00:35:45Z"

  class FakeAPI
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def get(path, query = {})
      @requests << [path, query]
      response = @responses.fetch(path)
      Marshal.load(Marshal.dump(response))
    end
  end

  def test_accepts_exact_squash_merge_with_all_required_jobs
    api = FakeAPI.new(valid_responses)

    decision = verifier(api).verify(
      repository: REPOSITORY,
      commit_sha: MERGE_SHA,
      base_ref: "main"
    )

    assert decision.reusable
    assert_equal "verified_pr_ci", decision.reason
    assert_equal 7, api.requests.length
    assert_equal HEAD_SHA, api.requests[5][1]["head_sha"]
  end

  def test_rejects_commit_without_one_exact_merged_pull_request
    responses = valid_responses
    responses[pulls_path] << responses[pulls_path].first.dup

    decision = verifier(FakeAPI.new(responses)).verify(
      repository: REPOSITORY,
      commit_sha: MERGE_SHA,
      base_ref: "main"
    )

    refute decision.reusable
    assert_equal "merged_pr_not_unique", decision.reason
  end

  def test_rejects_wrong_base_repository
    responses = valid_responses
    responses[pulls_path].first["base"]["repo"]["full_name"] = "attacker/fork"

    decision = verifier(FakeAPI.new(responses)).verify(
      repository: REPOSITORY,
      commit_sha: MERGE_SHA,
      base_ref: "main"
    )

    refute decision.reusable
    assert_equal "merged_pr_not_unique", decision.reason
  end

  def test_rejects_a_two_parent_merge_commit
    responses = valid_responses
    responses[commit_path]["parents"] << { "sha" => "d" * 40 }

    decision = verifier(FakeAPI.new(responses)).verify(
      repository: REPOSITORY,
      commit_sha: MERGE_SHA,
      base_ref: "main"
    )

    refute decision.reusable
    assert_equal "unsupported_merge_shape", decision.reason
  end


  def test_rejects_rebase_shape_whose_last_parent_is_not_the_pr_base
    responses = valid_responses
    responses[commit_path]["parents"] = [{ "sha" => "d" * 40 }]

    decision = verifier(FakeAPI.new(responses)).verify(
      repository: REPOSITORY,
      commit_sha: MERGE_SHA,
      base_ref: "main"
    )

    refute decision.reusable
    assert_equal "unsupported_merge_shape", decision.reason
  end

  def test_rejects_merge_tree_that_differs_from_tested_head
    responses = valid_responses
    responses[head_commit_path]["commit"]["tree"]["sha"] = "e" * 40

    decision = verifier(FakeAPI.new(responses)).verify(
      repository: REPOSITORY,
      commit_sha: MERGE_SHA,
      base_ref: "main"
    )

    refute decision.reusable
    assert_equal "merged_tree_not_tested", decision.reason
  end

  def test_rejects_pull_request_that_changes_ci_trust_boundary
    responses = valid_responses
    responses[files_path] = [{ "filename" => ".github/workflows/ci.yml" }]

    decision = verifier(FakeAPI.new(responses)).verify(
      repository: REPOSITORY,
      commit_sha: MERGE_SHA,
      base_ref: "main"
    )

    refute decision.reusable
    assert_equal "ci_trust_boundary_changed", decision.reason
  end

  def test_rejects_head_commit_associated_with_another_pull_request
    responses = valid_responses
    other_pull_request = Marshal.load(Marshal.dump(responses[head_pulls_path].first))
    other_pull_request["number"] = 91
    other_pull_request["base"]["ref"] = "release"
    responses[head_pulls_path] << other_pull_request

    decision = verifier(FakeAPI.new(responses)).verify(
      repository: REPOSITORY,
      commit_sha: MERGE_SHA,
      base_ref: "main"
    )

    refute decision.reusable
    assert_equal "head_pr_not_unique", decision.reason
  end

  def test_rejects_run_from_another_head_branch
    responses = valid_responses
    responses[runs_path]["workflow_runs"].first["head_branch"] = "other-branch"

    decision = verifier(FakeAPI.new(responses)).verify(
      repository: REPOSITORY,
      commit_sha: MERGE_SHA,
      base_ref: "main"
    )

    refute decision.reusable
    assert_equal "successful_pr_ci_not_found", decision.reason
  end

  def test_rejects_run_from_another_workflow_path
    responses = valid_responses
    responses[runs_path]["workflow_runs"].first["path"] =
      ".github/workflows/untrusted.yml"

    decision = verifier(FakeAPI.new(responses)).verify(
      repository: REPOSITORY,
      commit_sha: MERGE_SHA,
      base_ref: "main"
    )

    refute decision.reusable
    assert_equal "successful_pr_ci_not_found", decision.reason
  end

  def test_rejects_run_completed_after_merge
    responses = valid_responses
    responses[runs_path]["workflow_runs"].first["updated_at"] =
      "2026-08-08T00:36:45Z"

    decision = verifier(FakeAPI.new(responses)).verify(
      repository: REPOSITORY,
      commit_sha: MERGE_SHA,
      base_ref: "main"
    )

    refute decision.reusable
    assert_equal "successful_pr_ci_not_found", decision.reason
  end

  def test_rejects_skipped_or_missing_required_job
    responses = valid_responses
    responses[jobs_path]["jobs"].find do |job|
      job["name"] == "Minimum Xcode 16.0 / Native runtime"
    end["conclusion"] = "skipped"

    decision = verifier(FakeAPI.new(responses)).verify(
      repository: REPOSITORY,
      commit_sha: MERGE_SHA,
      base_ref: "main"
    )

    refute decision.reusable
    assert_equal "required_jobs_not_successful", decision.reason
  end

  def test_rejects_duplicate_required_job_names
    responses = valid_responses
    responses[jobs_path]["jobs"] << {
      "name" => "Classify changes",
      "conclusion" => "success"
    }
    responses[jobs_path]["total_count"] += 1

    decision = verifier(FakeAPI.new(responses)).verify(
      repository: REPOSITORY,
      commit_sha: MERGE_SHA,
      base_ref: "main"
    )

    refute decision.reusable
    assert_equal "required_jobs_not_successful", decision.reason
  end

  def test_rejects_truncated_job_response
    responses = valid_responses
    responses[jobs_path]["total_count"] += 1

    decision = verifier(FakeAPI.new(responses)).verify(
      repository: REPOSITORY,
      commit_sha: MERGE_SHA,
      base_ref: "main"
    )

    refute decision.reusable
    assert_equal "incomplete_job_page", decision.reason
  end

  def test_cli_fails_closed_without_token
    output = File.join(Dir.mktmpdir, "output")
    status = PocketRootPRCIReuse::CLI.run(
      [
        "--repository", REPOSITORY,
        "--commit", MERGE_SHA,
        "--base-ref", "main",
        "--output", output
      ],
      environment: {}
    )

    assert_equal 0, status
    assert_equal(
      "reused_pr_ci=false\nreuse_reason=missing_github_token\n",
      File.binread(output)
    )
  ensure
    FileUtils.remove_entry(File.dirname(output)) if output
  end

  private

  def verifier(api)
    PocketRootPRCIReuse::Verifier.new(api: api)
  end

  def pulls_path
    "/repos/#{REPOSITORY}/commits/#{MERGE_SHA}/pulls"
  end

  def head_pulls_path
    "/repos/#{REPOSITORY}/commits/#{HEAD_SHA}/pulls"
  end

  def runs_path
    "/repos/#{REPOSITORY}/actions/runs"
  end

  def files_path
    "/repos/#{REPOSITORY}/pulls/92/files"
  end

  def commit_path
    "/repos/#{REPOSITORY}/commits/#{MERGE_SHA}"
  end

  def head_commit_path
    "/repos/#{REPOSITORY}/commits/#{HEAD_SHA}"
  end

  def jobs_path
    "/repos/#{REPOSITORY}/actions/runs/1234/jobs"
  end

  def valid_responses
    jobs = PocketRootPRCIReuse::Verifier::REQUIRED_JOBS.map do |name|
      { "name" => name, "conclusion" => "success" }
    end
    pull_request = {
      "number" => 92,
      "merge_commit_sha" => MERGE_SHA,
      "merged_at" => MERGED_AT,
      "head" => {
        "sha" => HEAD_SHA,
        "ref" => "codex/rootfs-data-lifecycle",
        "repo" => { "full_name" => REPOSITORY }
      },
      "base" => {
        "ref" => "main",
        "sha" => "c" * 40,
        "repo" => { "full_name" => REPOSITORY }
      }
    }
    {
      pulls_path => [Marshal.load(Marshal.dump(pull_request))],
      files_path => [{ "filename" => "Sources/PocketRoot/Feature.swift" }],
      head_pulls_path => [Marshal.load(Marshal.dump(pull_request))],
      commit_path => {
        "sha" => MERGE_SHA,
        "parents" => [{ "sha" => "c" * 40 }],
        "commit" => { "tree" => { "sha" => "f" * 40 } }
      },
      head_commit_path => {
        "sha" => HEAD_SHA,
        "commit" => { "tree" => { "sha" => "f" * 40 } }
      },
      runs_path => {
        "total_count" => 1,
        "workflow_runs" => [
          {
            "id" => 1234,
            "name" => "CI",
            "path" => ".github/workflows/ci.yml",
            "event" => "pull_request",
            "head_sha" => HEAD_SHA,
            "head_branch" => "codex/rootfs-data-lifecycle",
            "head_repository" => { "full_name" => REPOSITORY },
            "conclusion" => "success",
            "updated_at" => "2026-08-08T00:34:45Z",
            "pull_requests" => []
          }
        ]
      },
      jobs_path => {
        "total_count" => jobs.length,
        "jobs" => jobs
      }
    }
  end
end
