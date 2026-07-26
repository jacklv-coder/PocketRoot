#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require_relative "../../Scripts/rootfs-license-review-results"

class RootFSLicenseReviewResultsTests < Minitest::Test
  REPOSITORY_ROOT = Pathname(__dir__).join("../..").realpath
  REVIEW_PATH =
    REPOSITORY_ROOT.join("Compliance/RootFS/v0.3.3/LICENSE-REVIEW.json")
  SOURCE_ACQUISITION_PATH =
    REPOSITORY_ROOT.join(
      "Compliance/RootFS/v0.3.3/SOURCE-ACQUISITION.json"
    )
  SOURCE_INVENTORY_PATH =
    REPOSITORY_ROOT.join("Compliance/RootFS/v0.3.3/SOURCE-INVENTORY.json")
  RESULTS_PATH =
    REPOSITORY_ROOT.join(
      "Compliance/RootFS/v0.3.3/LICENSE-REVIEW-RESULTS.json"
    )
  SCRIPT_PATH =
    REPOSITORY_ROOT.join("Scripts/rootfs-license-review-results.rb")

  def setup
    @review_bytes = REVIEW_PATH.binread
    @review = JSON.parse(@review_bytes)
    @source_acquisition_bytes = SOURCE_ACQUISITION_PATH.binread
    @source_acquisition = JSON.parse(@source_acquisition_bytes)
    @source_inventory = JSON.parse(SOURCE_INVENTORY_PATH.binread)
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
        source_acquisition: @source_acquisition,
        source_inventory: @source_inventory,
        license_review_bytes: changed_review_bytes,
        source_acquisition_bytes: @source_acquisition_bytes
      )
    end

    assert_includes error.message,
      "do not match LICENSE-REVIEW.json bytes"
  end

  def test_rejects_invalid_candidate_manifest_with_matching_binding
    @review.fetch("sources").first
      .fetch("candidateEvidence").first["sha256"] = "not-a-sha256"
    @review_bytes = "#{JSON.pretty_generate(@review)}\n"
    @results["licenseReviewManifestSha256"] =
      Digest::SHA256.hexdigest(@review_bytes)

    error = assert_raises(
      RootFSLicenseReviewResults::ValidationError
    ) { validate }

    assert_includes error.message, "invalid manifest"
    assert_includes error.message, "invalid sha256"
  end

  def test_reports_malformed_candidate_manifest_as_validation_error
    @review.fetch("sources").first.delete("openReviewItems")
    @review_bytes = "#{JSON.pretty_generate(@review)}\n"
    @results["licenseReviewManifestSha256"] =
      Digest::SHA256.hexdigest(@review_bytes)

    error = assert_raises(
      RootFSLicenseReviewResults::ValidationError
    ) { validate }

    assert_includes error.message, "invalid manifest"
    assert_includes error.message, "openReviewItems"
  end

  def test_rejects_invalid_source_inventory
    @source_inventory.fetch("archive")["sha256"] = "0" * 64

    error = assert_raises(
      RootFSLicenseReviewResults::ValidationError
    ) { validate }

    assert_includes error.message, "invalid manifest"
    assert_includes error.message, "pinned RootFS archive"
  end

  def test_rejects_license_review_object_not_backed_by_supplied_bytes
    @review["status"] = "changed"

    error = assert_raises(
      RootFSLicenseReviewResults::ValidationError
    ) { validate }

    assert_includes error.message,
      "license review manifest object does not match supplied bytes"
  end

  def test_rejects_source_acquisition_object_not_backed_by_supplied_bytes
    @source_acquisition.fetch("sources").first
      .fetch("aportsSnapshot")["sha512"] = "0" * 128

    error = assert_raises(
      RootFSLicenseReviewResults::ValidationError
    ) { validate }

    assert_includes error.message,
      "source acquisition manifest object does not match supplied bytes"
  end

  def test_rejects_numeric_type_mismatch_between_object_and_bytes
    @source_acquisition.fetch("sources").first
      .fetch("aportsSnapshot")["regularFileCount"] = 16.0

    error = assert_raises(
      RootFSLicenseReviewResults::ValidationError
    ) { validate }

    assert_includes error.message,
      "source acquisition manifest object does not match supplied bytes"
  end

  def test_two_argument_cli_uses_manifests_next_to_custom_review
    Dir.mktmpdir("rootfs-license-review-results") do |directory|
      bundle = Pathname(directory)
      [
        REVIEW_PATH,
        SOURCE_ACQUISITION_PATH,
        SOURCE_INVENTORY_PATH,
        RESULTS_PATH
      ].each do |source|
        FileUtils.cp(source, bundle.join(source.basename))
      end

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        SCRIPT_PATH.to_s,
        bundle.join(RESULTS_PATH.basename).to_s,
        bundle.join(REVIEW_PATH.basename).to_s,
        chdir: REPOSITORY_ROOT.to_s
      )

      assert status.success?, stderr
      assert_includes stdout,
        "RootFS license review results are valid (10 source origins)."
    end
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
      source_acquisition: @source_acquisition,
      source_inventory: @source_inventory,
      license_review_bytes: @review_bytes,
      source_acquisition_bytes: @source_acquisition_bytes
    )
  end
end
