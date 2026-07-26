#!/usr/bin/env ruby

require "digest"
require "json"
require "minitest/autorun"
require "pathname"
require_relative "../../Scripts/rootfs-license-review-results"

class RootFSLicenseReviewResultsTests < Minitest::Test
  REPOSITORY_ROOT = Pathname(__dir__).join("../..").realpath
  REVIEW_PATH =
    REPOSITORY_ROOT.join("Compliance/RootFS/v0.3.3/LICENSE-REVIEW.json")
  RESULTS_PATH =
    REPOSITORY_ROOT.join(
      "Compliance/RootFS/v0.3.3/LICENSE-REVIEW-RESULTS.json"
    )

  def setup
    @review_bytes = REVIEW_PATH.binread
    @review = JSON.parse(@review_bytes)
    @results = JSON.parse(RESULTS_PATH.binread)
  end

  def test_validates_pinned_engineering_review_results
    sources = validate

    assert_equal 10, sources.length
    assert_equal 21,
      sources.sum { |entry| entry.fetch("candidateResults").length }
    assert_equal 8,
      sources.count { |entry| !entry.fetch("remainingReviewItems").empty? }
    assert_equal %w[libc-dev zlib],
      sources
        .select { |entry| entry.fetch("remainingReviewItems").empty? }
        .map { |entry| entry.fetch("sourceOrigin") }
  end

  def test_rejects_legal_or_redistribution_approval
    @results["legalReviewApproved"] = true

    error = assert_raises(
      RootFSLicenseReviewResults::ValidationError
    ) { validate }

    assert_includes error.message, "open release gates"
  end

  def test_rejects_missing_candidate_result
    @results.fetch("sources").fetch(2).fetch("candidateResults").pop

    error = assert_raises(
      RootFSLicenseReviewResults::ValidationError
    ) { validate }

    assert_includes error.message, "cover every indexed candidate"
  end

  def test_rejects_candidate_digest_drift
    candidate =
      @results.fetch("sources").fetch(3).fetch("candidateResults").first
    candidate["sha256"] = "0" * 64

    error = assert_raises(
      RootFSLicenseReviewResults::ValidationError
    ) { validate }

    assert_includes error.message, "does not match the indexed evidence"
  end

  def test_rejects_incomplete_review_item_disposition
    @results.fetch("sources").first.fetch("remainingReviewItems").pop

    error = assert_raises(
      RootFSLicenseReviewResults::ValidationError
    ) { validate }

    assert_includes error.message, "disposition"
  end

  def test_rejects_license_review_manifest_drift
    @review["status"] = "changed"
    changed_review_bytes = "#{JSON.pretty_generate(@review)}\n"

    error = assert_raises(
      RootFSLicenseReviewResults::ValidationError
    ) do
      RootFSLicenseReviewResults.validate_manifest(
        @results,
        @review,
        license_review_bytes: changed_review_bytes
      )
    end

    assert_includes error.message,
      "do not match LICENSE-REVIEW.json bytes"
  end

  def test_rejects_summary_count_drift
    @results["reviewedCandidateCount"] = 20

    error = assert_raises(
      RootFSLicenseReviewResults::ValidationError
    ) { validate }

    assert_includes error.message, "summary counts"
  end

  def test_requires_revisiting_bundle_gate_when_all_coverage_is_complete
    @results.fetch("sources").each do |entry|
      entry["licenseTextCoverage"] = "complete"
    end

    error = assert_raises(
      RootFSLicenseReviewResults::ValidationError
    ) { validate }

    assert_includes error.message,
      "completeLicenseTextBundlePresent must be revisited"
  end

  private

  def validate
    RootFSLicenseReviewResults.validate_manifest(
      @results,
      @review,
      license_review_bytes: @review_bytes
    )
  end
end
