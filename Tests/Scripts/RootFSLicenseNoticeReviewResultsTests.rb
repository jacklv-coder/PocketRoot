#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require_relative "../../Scripts/rootfs-license-notice-review-results"

class RootFSLicenseNoticeReviewResultsTests < Minitest::Test
  REPOSITORY_ROOT = Pathname(__dir__).join("../..").realpath
  COMPLIANCE_ROOT = REPOSITORY_ROOT.join("Compliance/RootFS/v0.3.3")
  RESULTS_PATH =
    COMPLIANCE_ROOT.join("LICENSE-NOTICE-REVIEW-RESULTS.json")
  CANDIDATE_PATH =
    COMPLIANCE_ROOT.join("LICENSE-NOTICE-CANDIDATES.json")
  PRIOR_RESULTS_PATH =
    COMPLIANCE_ROOT.join("LICENSE-REVIEW-RESULTS.json")
  REVIEW_PATH = COMPLIANCE_ROOT.join("LICENSE-REVIEW.json")
  SOURCE_ACQUISITION_PATH =
    COMPLIANCE_ROOT.join("SOURCE-ACQUISITION.json")
  SOURCE_INVENTORY_PATH =
    COMPLIANCE_ROOT.join("SOURCE-INVENTORY.json")
  SCRIPT_PATH =
    REPOSITORY_ROOT.join(
      "Scripts/rootfs-license-notice-review-results.rb"
    )

  def setup
    @candidate_bytes = CANDIDATE_PATH.binread
    @prior_results_bytes = PRIOR_RESULTS_PATH.binread
    @review_bytes = REVIEW_PATH.binread
    @source_acquisition_bytes = SOURCE_ACQUISITION_PATH.binread
    @results = JSON.parse(RESULTS_PATH.binread)
    @candidates = JSON.parse(@candidate_bytes)
    @prior_results = JSON.parse(@prior_results_bytes)
    @review = JSON.parse(@review_bytes)
    @source_acquisition = JSON.parse(@source_acquisition_bytes)
    @source_inventory = JSON.parse(SOURCE_INVENTORY_PATH.binread)
  end

  def test_validates_pinned_candidate_review_results
    validated = validate

    assert_equal 8, validated.fetch(:sources).length
    assert_equal 8, validated.fetch(:remote_payloads).length
    assert_equal 46, validated.fetch(:aports_paths).length
    assert_equal 75, @results.fetch("reviewedPayloadFileCount")
    assert_equal 6,
      @results.fetch("sourceOriginsWithRemainingReviewItems")
    assert_equal %w[apk-tools pax-utils],
      @results.fetch("sources")
        .select { |source| source.fetch("remainingReviewItems").empty? }
        .map { |source| source.fetch("sourceOrigin") }
  end

  def test_rejects_legal_or_redistribution_approval
    @results["legalReviewApproved"] = true

    error = assert_raises(
      RootFSLicenseNoticeReviewResults::ValidationError
    ) { validate }

    assert_includes error.message, "open release gates"
  end

  def test_rejects_candidate_manifest_digest_drift
    @candidates["status"] = "changed"

    error = assert_raises(
      RootFSLicenseNoticeReviewResults::ValidationError
    ) { validate }

    assert_includes error.message, "candidate manifest bytes"
  end

  def test_rejects_incomplete_review_item_disposition
    @results.fetch("sources").first.fetch("remainingReviewItems").clear

    error = assert_raises(
      RootFSLicenseNoticeReviewResults::ValidationError
    ) { validate }

    assert_includes error.message, "disposition"
  end

  def test_rejects_conclusion_that_does_not_match_open_items
    @results.fetch("sources").first["engineeringConclusion"] =
      "candidate-material-complete-engineering-only"

    error = assert_raises(
      RootFSLicenseNoticeReviewResults::ValidationError
    ) { validate }

    assert_includes error.message, "conclusion"
  end

  def test_rejects_payload_count_drift
    @results["reviewedPayloadFileCount"] = 74

    error = assert_raises(
      RootFSLicenseNoticeReviewResults::ValidationError
    ) { validate }

    assert_includes error.message, "payload counts"
  end

  def test_requires_revisiting_completion_gate_when_no_items_remain
    @results.fetch("sources").each do |source|
      source["resolvedReviewItems"] += source["remainingReviewItems"]
      source["remainingReviewItems"] = []
      source["engineeringConclusion"] =
        "candidate-material-complete-engineering-only"
    end
    @results["sourceOriginsWithRemainingReviewItems"] = 0

    error = assert_raises(
      RootFSLicenseNoticeReviewResults::ValidationError
    ) { validate }

    assert_includes error.message,
      "completePackageLicenseNoticeSetPresent must be revisited"
  end

  def test_verifies_reviewed_payload_tree
    Dir.mktmpdir("rootfs-notice-reviewed-bundle") do |directory|
      root = Pathname(directory)
      root.join("evidence/origin").mkpath
      root.join("licenses").mkpath
      root.join("supplemental/aports/origin").mkpath
      evidence = "reviewed evidence\n"
      license = "reviewed license\n"
      patch = "reviewed patch\n"
      root.join("evidence/origin/LICENSE").binwrite(evidence)
      root.join("licenses/License.txt").binwrite(license)
      root.join("supplemental/aports/origin/fix.patch").binwrite(patch)
      validated = reviewed_bundle_fixture(evidence, license)
      tree_sha256 =
        reviewed_tree_sha256(
          root,
          %w[
            evidence/origin/LICENSE
            licenses/License.txt
            supplemental/aports/origin/fix.patch
          ]
        )

      count =
        RootFSLicenseNoticeReviewResults.verify_reviewed_bundle(
          root,
          validated,
          tree_sha256
        )

      assert_equal 3, count
    end
  end

  def test_rejects_reviewed_payload_tree_drift
    Dir.mktmpdir("rootfs-notice-reviewed-bundle") do |directory|
      root = Pathname(directory)
      root.join("evidence/origin").mkpath
      root.join("licenses").mkpath
      root.join("supplemental/aports/origin").mkpath
      evidence = "reviewed evidence\n"
      license = "reviewed license\n"
      root.join("evidence/origin/LICENSE").binwrite(evidence)
      root.join("licenses/License.txt").binwrite(license)
      root.join("supplemental/aports/origin/fix.patch")
        .binwrite("changed patch\n")

      error = assert_raises(
        RootFSLicenseNoticeReviewResults::ValidationError
      ) do
        RootFSLicenseNoticeReviewResults.verify_reviewed_bundle(
          root,
          reviewed_bundle_fixture(evidence, license),
          "0" * 64
        )
      end

      assert_includes error.message, "tree digest mismatch"
    end
  end

  def test_rejects_symlink_in_reviewed_payload_tree
    Dir.mktmpdir("rootfs-notice-reviewed-bundle") do |directory|
      root = Pathname(directory)
      root.join("evidence/origin").mkpath
      root.join("licenses").mkpath
      root.join("supplemental/aports/origin").mkpath
      evidence = "reviewed evidence\n"
      license = "reviewed license\n"
      root.join("evidence/origin/LICENSE").binwrite(evidence)
      root.join("licenses/License.txt").binwrite(license)
      root.join("supplemental/aports/origin/fix.patch")
        .make_symlink(root.join("evidence/origin/LICENSE"))

      error = assert_raises(
        RootFSLicenseNoticeReviewResults::ValidationError
      ) do
        RootFSLicenseNoticeReviewResults.verify_reviewed_bundle(
          root,
          reviewed_bundle_fixture(evidence, license),
          "0" * 64
        )
      end

      assert_includes error.message, "link or special node"
    end
  end

  def test_rejects_symlink_outside_reviewed_payload_tree
    Dir.mktmpdir("rootfs-notice-reviewed-bundle") do |directory|
      root = Pathname(directory)
      root.join("evidence/origin").mkpath
      root.join("licenses").mkpath
      root.join("supplemental/aports/origin").mkpath
      evidence = "reviewed evidence\n"
      license = "reviewed license\n"
      patch = "reviewed patch\n"
      root.join("evidence/origin/LICENSE").binwrite(evidence)
      root.join("licenses/License.txt").binwrite(license)
      root.join("supplemental/aports/origin/fix.patch").binwrite(patch)
      root.join("BUNDLE-RECEIPT.json")
        .make_symlink(root.join("evidence/origin/LICENSE"))

      error = assert_raises(
        RootFSLicenseNoticeReviewResults::ValidationError
      ) do
        RootFSLicenseNoticeReviewResults.verify_reviewed_bundle(
          root,
          reviewed_bundle_fixture(evidence, license),
          reviewed_tree_sha256(
            root,
            %w[
              evidence/origin/LICENSE
              licenses/License.txt
              supplemental/aports/origin/fix.patch
            ]
          )
        )
      end

      assert_includes error.message, "link or special node"
      assert_includes error.message, "BUNDLE-RECEIPT.json"
    end
  end

  def test_custom_results_path_uses_adjacent_manifests
    Dir.mktmpdir("rootfs-notice-review-results") do |directory|
      root = Pathname(directory)
      [
        RESULTS_PATH,
        CANDIDATE_PATH,
        PRIOR_RESULTS_PATH,
        REVIEW_PATH,
        SOURCE_ACQUISITION_PATH,
        SOURCE_INVENTORY_PATH
      ].each do |source|
        FileUtils.cp(source, root.join(source.basename))
      end

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        SCRIPT_PATH.to_s,
        root.join(RESULTS_PATH.basename).to_s,
        chdir: REPOSITORY_ROOT.to_s
      )

      assert status.success?, stderr
      assert_includes stdout,
        "candidate review results are valid (8 source origins)."
    end
  end

  private

  def validate
    RootFSLicenseNoticeReviewResults.validate_manifest(
      @results,
      @candidates,
      prior_results: @prior_results,
      license_review: @review,
      source_acquisition: @source_acquisition,
      source_inventory: @source_inventory,
      candidate_bytes: @candidate_bytes,
      prior_results_bytes: @prior_results_bytes,
      license_review_bytes: @review_bytes,
      source_acquisition_bytes: @source_acquisition_bytes
    )
  end

  def reviewed_bundle_fixture(evidence, license)
    {
      existing_evidence: {
        "evidence/origin/LICENSE" => {
          "sha256" => Digest::SHA256.hexdigest(evidence)
        }
      },
      remote_payloads: [
        {
          "outputPath" => "licenses/License.txt",
          "sha256" => Digest::SHA256.hexdigest(license)
        }
      ],
      aports_paths: ["aports/origin/fix.patch"]
    }
  end

  def reviewed_tree_sha256(root, paths)
    lines = paths.sort.map do |relative|
      "#{Digest::SHA256.file(root.join(relative)).hexdigest}  #{relative}\n"
    end
    Digest::SHA256.hexdigest(lines.join)
  end
end
