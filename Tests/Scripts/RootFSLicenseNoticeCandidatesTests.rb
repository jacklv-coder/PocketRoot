#!/usr/bin/env ruby

require "json"
require "minitest/autorun"
require "pathname"
require_relative "../../Scripts/rootfs-license-notice-candidates"

class RootFSLicenseNoticeCandidatesTests < Minitest::Test
  ROOT = Pathname(__dir__).join("../..").realpath
  DIRECTORY = ROOT.join("Compliance/RootFS/v0.3.3")

  def setup
    @candidate_bytes =
      DIRECTORY.join("LICENSE-NOTICE-CANDIDATES.json").binread
    @candidate = JSON.parse(@candidate_bytes)
    @results_bytes =
      DIRECTORY.join("LICENSE-REVIEW-RESULTS.json").binread
    @results = JSON.parse(@results_bytes)
    @review_bytes = DIRECTORY.join("LICENSE-REVIEW.json").binread
    @review = JSON.parse(@review_bytes)
    @source_bytes = DIRECTORY.join("SOURCE-ACQUISITION.json").binread
    @source = JSON.parse(@source_bytes)
    @inventory =
      JSON.parse(DIRECTORY.join("SOURCE-INVENTORY.json").binread)
  end

  def test_validates_complete_open_origin_candidate_index
    validated = validate

    assert_equal 8, validated.fetch(:sources).length
    assert_equal 8, validated.fetch(:remote_payloads).length
    assert_equal 21, validated.fetch(:existing_evidence_paths).length
    assert_equal 46, validated.fetch(:aports_paths).length
  end

  def test_rejects_review_results_digest_drift
    @candidate["licenseReviewResultsSha256"] = "0" * 64

    error = assert_raises(
      RootFSLicenseNoticeCandidates::ValidationError
    ) { validate }

    assert_includes error.message, "LICENSE-REVIEW-RESULTS.json bytes"
  end

  def test_rejects_opening_release_gates
    @candidate["engineeringReviewApproved"] = true

    error = assert_raises(
      RootFSLicenseNoticeCandidates::ValidationError
    ) { validate }

    assert_includes error.message, "open release gates"
  end

  def test_rejects_missing_open_source_origin
    @candidate.fetch("sources").pop

    error = assert_raises(
      RootFSLicenseNoticeCandidates::ValidationError
    ) { validate }

    assert_includes error.message, "every open source origin"
  end

  def test_rejects_unsafe_supplemental_aports_path
    @candidate.fetch("sources").fetch(2)
      .fetch("supplementalAportsPaths")[0] = "../outside.patch"

    error = assert_raises(
      RootFSLicenseNoticeCandidates::ValidationError
    ) { validate }

    assert_includes error.message, "unsafe path"
  end

  def test_rejects_missing_declared_license_reference
    @candidate.fetch("sources").fetch(5)
      .fetch("referenceLicensePaths").delete("licenses/BSD-2-Clause.txt")

    error = assert_raises(
      RootFSLicenseNoticeCandidates::ValidationError
    ) { validate }

    assert_includes error.message, "do not cover declarations"
  end

  def test_rejects_duplicate_remote_output_path
    payloads = @candidate.fetch("remotePayloads")
    payloads.fetch(1)["outputPath"] = payloads.fetch(0).fetch("outputPath")

    error = assert_raises(
      RootFSLicenseNoticeCandidates::ValidationError
    ) { validate }

    assert_includes error.message, "must be unique"
  end

  def test_rejects_incomplete_supplemental_aports_set
    @candidate.fetch("sources").fetch(3)
      .fetch("supplementalAportsPaths").pop

    error = assert_raises(
      RootFSLicenseNoticeCandidates::ValidationError
    ) { validate }

    assert_includes error.message, "coverage is incomplete"
  end

  def test_rejects_remote_evidence_assigned_to_wrong_origin
    @candidate.fetch("sources").first
      .fetch("remoteEvidencePaths").clear

    error = assert_raises(
      RootFSLicenseNoticeCandidates::ValidationError
    ) { validate }

    assert_includes error.message, "remote evidence paths"
  end

  def test_rejects_overlapping_materialized_output_paths
    payloads = @candidate.fetch("remotePayloads")
    payloads.fetch(0)["outputPath"] = "licenses/collision"
    payloads.fetch(1)["outputPath"] = "licenses/collision/child"
    @candidate.fetch("sources").fetch(5)["referenceLicensePaths"]
      .map! do |path|
        path == "licenses/BSD-2-Clause.txt" ? "licenses/collision/child" : path
      end
    @candidate.fetch("sources").fetch(6)["referenceLicensePaths"] =
      ["licenses/collision"]

    error = assert_raises(
      RootFSLicenseNoticeCandidates::ValidationError
    ) { validate }

    assert_includes error.message, "output paths overlap"
  end

  def test_rejects_package_payload_path_for_another_origin
    payload = @candidate.fetch("remotePayloads").fetch(6)
    payload["outputPath"] = "supplemental/pax-utils/openssl-README.md"
    @candidate.fetch("sources").fetch(6)["remoteEvidencePaths"] =
      [payload.fetch("outputPath")]

    error = assert_raises(
      RootFSLicenseNoticeCandidates::ValidationError
    ) { validate }

    assert_includes error.message, "under its source origin"
  end

  def test_rejects_results_object_not_backed_by_supplied_bytes
    @results["reviewedCandidateCount"] = 20

    error = assert_raises(
      RootFSLicenseNoticeCandidates::ValidationError
    ) { validate }

    assert_includes error.message, "LICENSE-REVIEW-RESULTS.json bytes"
  end

  private

  def validate
    RootFSLicenseNoticeCandidates.validate_manifest(
      @candidate,
      @results,
      license_review: @review,
      source_acquisition: @source,
      source_inventory: @inventory,
      results_bytes: @results_bytes,
      license_review_bytes: @review_bytes,
      source_acquisition_bytes: @source_bytes
    )
  end
end
