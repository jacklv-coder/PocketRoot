#!/usr/bin/env ruby

require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require_relative "../../Scripts/rootfs-corresponding-source-review-results"

class RootFSCorrespondingSourceReviewResultsTests < Minitest::Test
  REPOSITORY_ROOT = Pathname(__dir__).join("../..").realpath
  DIRECTORY = REPOSITORY_ROOT.join("Compliance/RootFS/v0.3.3")
  RESULTS_PATH =
    DIRECTORY.join("CORRESPONDING-SOURCE-REVIEW-RESULTS.json")
  ACQUISITION_PATH = DIRECTORY.join("SOURCE-ACQUISITION.json")
  INVENTORY_PATH = DIRECTORY.join("SOURCE-INVENTORY.json")
  SCRIPT =
    REPOSITORY_ROOT.join(
      "Scripts/rootfs-corresponding-source-review-results.rb"
    )

  def setup
    @results = JSON.parse(RESULTS_PATH.read)
    @acquisition_bytes = ACQUISITION_PATH.binread
    @acquisition = JSON.parse(@acquisition_bytes)
    @inventory = JSON.parse(INVENTORY_PATH.read)
  end

  def test_real_review_results_cover_all_candidate_source_material
    sources = validate

    assert_equal 10, sources.length
    assert_equal 130,
      @results.fetch("reviewedCanonicalAportsEntryCount")
    assert_equal 9, @results.fetch("reviewedDistfileCount")
    assert_equal 0,
      @results.fetch("sourceOriginsWithRemainingMaterialItems")
    assert sources.all? do |source|
      source.fetch("materialCoverage") == "complete" &&
        source.fetch("remainingReviewItems").empty?
    end
    refute @results.fetch("completeCorrespondingSourceBundlePresent")
    refute @results.fetch("correspondingSourceDeliveryApproved")
    refute @results.fetch("redistributionApproved")
  end

  def test_command_line_validator_accepts_real_documents
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      chdir: REPOSITORY_ROOT.to_s
    )

    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout,
      "RootFS corresponding-source candidate review results are valid"
  end

  def test_command_line_validator_rejects_special_acquisition_file
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      SCRIPT.to_s,
      RESULTS_PATH.to_s,
      "/dev/null",
      INVENTORY_PATH.to_s,
      chdir: REPOSITORY_ROOT.to_s
    )

    refute status.success?
    assert_includes stderr,
      "source acquisition manifest is not a real regular file"
  end

  def test_rejects_source_acquisition_byte_drift
    @results["sourceAcquisitionSha256"] = "0" * 64

    error = assert_raises(
      RootFSCorrespondingSourceReviewResults::ValidationError
    ) { validate }
    assert_includes error.message,
      "do not match source acquisition bytes"
  end

  def test_rejects_missing_source_origin
    @results.fetch("sources").pop

    error = assert_raises(
      RootFSCorrespondingSourceReviewResults::ValidationError
    ) { validate }
    assert_includes error.message, "must cover every source origin"
  end

  def test_rejects_canonical_aports_entry_count_drift
    @results.fetch("sources").first[
      "reviewedCanonicalAportsEntryCount"
    ] += 1

    error = assert_raises(
      RootFSCorrespondingSourceReviewResults::ValidationError
    ) { validate }
    assert_includes error.message,
      "does not match alpine-baselayout"
  end

  def test_rejects_unresolved_material_item
    source = @results.fetch("sources").first
    source["remainingReviewItems"] = ["collect-missing-patch"]

    error = assert_raises(
      RootFSCorrespondingSourceReviewResults::ValidationError
    ) { validate }
    assert_includes error.message,
      "does not match alpine-baselayout"
  end

  def test_rejects_release_gate_claim
    @results["correspondingSourceDeliveryApproved"] = true

    error = assert_raises(
      RootFSCorrespondingSourceReviewResults::ValidationError
    ) { validate }
    assert_includes error.message, "do not preserve open release gates"
  end

  def test_rejects_source_inventory_release_gate_claim
    @inventory["correspondingSourceDeliveryApproved"] = true

    error = assert_raises(
      RootFSCorrespondingSourceReviewResults::ValidationError
    ) { validate }
    assert_includes error.message,
      "source inventory does not preserve corresponding-source release gates"
  end

  def test_rejects_inventory_binary_package_drift
    @inventory.fetch("sourceOrigins").first["binaryPackages"] = ["other"]

    error = assert_raises(
      RootFSCorrespondingSourceReviewResults::ValidationError
    ) { validate }
    assert_includes error.message,
      "corresponding-source review inputs are invalid"
  end

  def test_rejects_non_boolean_copyleft_flags
    @inventory.fetch("sourceOrigins").first[
      "containsDeclaredCopyleft"
    ] = "true"
    @results.fetch("sources").first[
      "containsDeclaredCopyleft"
    ] = "true"

    error = assert_raises(
      RootFSCorrespondingSourceReviewResults::ValidationError
    ) { validate }
    assert_includes error.message,
      "does not match alpine-baselayout"
  end

  def test_rejects_distfile_count_drift
    @results["reviewedDistfileCount"] += 1

    error = assert_raises(
      RootFSCorrespondingSourceReviewResults::ValidationError
    ) { validate }
    assert_includes error.message,
      "totals do not match pinned inputs"
  end

  private

  def validate
    RootFSCorrespondingSourceReviewResults.validate_manifest(
      @results,
      @acquisition,
      @inventory,
      source_acquisition_bytes: @acquisition_bytes
    )
  end
end
