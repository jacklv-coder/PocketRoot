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
    assert_equal 13, validated.fetch(:remote_payloads).length
    assert_equal 26, validated.fetch(:existing_evidence_paths).length
    assert_equal 47, validated.fetch(:aports_paths).length
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

  def test_pins_alpine_keys_license_decision_evidence
    payload = @candidate.fetch("remotePayloads").find do |candidate|
      candidate["sourceOrigin"] == "alpine-keys"
    end
    source = @candidate.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "alpine-keys"
    end

    assert_equal(
      ["https://gitlab.alpinelinux.org/alpine/aports/-/commit/" \
       "7f1f035cf4f7bbea5cf7b65f9bbedc311d735596.patch"],
      payload.fetch("retrievalURLs")
    )
    assert_equal 772, payload.fetch("byteCount")
    assert_equal(
      "a939e8baa52febea02d5bcfcc306822827eac3fd979a637c7723c84af3487e3e",
      payload.fetch("sha256")
    )
    assert_equal(
      ["supplemental/alpine-keys/license-decision.patch"],
      source.fetch("remoteEvidencePaths")
    )
  end

  def test_pins_exact_curl_license_for_ca_bundle_generator
    payloads = @candidate.fetch("remotePayloads").select do |candidate|
      candidate["sourceOrigin"] == "ca-certificates"
    end
    source = @candidate.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "ca-certificates"
    end
    reviewed_script = @review.fetch("sources")
      .find { |candidate| candidate.fetch("sourceOrigin") == "ca-certificates" }
      .fetch("candidateEvidence")
      .find { |evidence| evidence.fetch("outputPath").end_with?("mk-ca-bundle.pl") }

    assert_equal 2, payloads.length
    assert_equal(
      [
        "https://raw.githubusercontent.com/curl/curl/" \
        "3fdc4bdb5b00835a1d04cf160cd61fe7f8feb477/lib/mk-ca-bundle.pl",
        "https://raw.githubusercontent.com/curl/curl/" \
        "3fdc4bdb5b00835a1d04cf160cd61fe7f8feb477/COPYING"
      ],
      payloads.flat_map { |payload| payload.fetch("retrievalURLs") }
    )
    assert_equal [20_863, 1_088],
      payloads.map { |payload| payload.fetch("byteCount") }
    assert_equal reviewed_script.fetch("sha256"),
      payloads.first.fetch("sha256")
    assert_equal(
      "db3c4a3b3695a0f317a0c5176acd2f656d18abc45b3ee78e50935a78eb1e132e",
      payloads.last.fetch("sha256")
    )
    assert_equal(
      %w[
        supplemental/ca-certificates/curl-mk-ca-bundle.pl
        supplemental/ca-certificates/curl-COPYING
      ],
      source.fetch("remoteEvidencePaths")
    )
  end

  def test_pins_busybox_configuration_for_bzip2_license_review
    source = @candidate.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end

    assert_includes(
      source.fetch("supplementalAportsPaths"),
      "aports/busybox/busyboxconfig"
    )
    assert_includes(
      source.fetch("existingEvidencePaths"),
      "evidence/busybox/bzip2-LICENSE"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "confirm-enabled-bzip2-license-and-attribution-coverage"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "review-other-bundled-third-party-license-and-attribution-coverage"
    )
  end

  def test_pins_enabled_busybox_ash_math_inline_notices
    source = @candidate.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    review_source = @review.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    evidence = review_source.fetch("candidateEvidence").find do |candidate|
      candidate.fetch("outputPath") == "evidence/busybox/shell-math.c"
    end

    assert_includes(
      source.fetch("existingEvidencePaths"),
      "evidence/busybox/shell-math.c"
    )
    assert_includes(
      source.fetch("supplementalAportsPaths"),
      "aports/busybox/busyboxconfig"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "confirm-enabled-ash-math-license-and-attribution-coverage"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "review-other-bundled-third-party-license-and-attribution-coverage"
    )
    assert_equal "busybox-1.36.1/shell/math.c", evidence.fetch("member")
    assert_equal 26_578, evidence.fetch("byteCount")
    assert_equal(
      "8f2d57454d233b67662047cd3411c77ecde7e428ef1f6652d66f177b1d06e2f3",
      evidence.fetch("sha256")
    )
    assert_equal(
      %w[inline-license-notice attribution],
      evidence.fetch("evidenceKinds")
    )
  end

  def test_pins_enabled_busybox_env_inline_notice
    source = @candidate.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    review_source = @review.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    evidence = review_source.fetch("candidateEvidence").find do |candidate|
      candidate.fetch("outputPath") == "evidence/busybox/coreutils-env.c"
    end

    assert_includes(
      source.fetch("existingEvidencePaths"),
      "evidence/busybox/coreutils-env.c"
    )
    assert_includes(
      source.fetch("supplementalAportsPaths"),
      "aports/busybox/busyboxconfig"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "confirm-enabled-env-license-and-attribution-coverage"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "review-other-bundled-third-party-license-and-attribution-coverage"
    )
    assert_equal "busybox-1.36.1/coreutils/env.c", evidence.fetch("member")
    assert_equal 4_753, evidence.fetch("byteCount")
    assert_equal(
      "730d258bcbeeef301fc00611d0e325958f3f378576af54c524f9be662b0ac757",
      evidence.fetch("sha256")
    )
    assert_equal(
      %w[inline-license-notice attribution],
      evidence.fetch("evidenceKinds")
    )
  end

  def test_pins_enabled_busybox_echo_inline_notice
    source = @candidate.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    review_source = @review.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    evidence = review_source.fetch("candidateEvidence").find do |candidate|
      candidate.fetch("outputPath") == "evidence/busybox/coreutils-echo.c"
    end

    assert_includes(
      source.fetch("existingEvidencePaths"),
      "evidence/busybox/coreutils-echo.c"
    )
    assert_includes(
      source.fetch("supplementalAportsPaths"),
      "aports/busybox/busyboxconfig"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "confirm-enabled-echo-license-and-attribution-coverage"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "review-other-bundled-third-party-license-and-attribution-coverage"
    )
    assert_equal "busybox-1.36.1/coreutils/echo.c", evidence.fetch("member")
    assert_equal 9_960, evidence.fetch("byteCount")
    assert_equal(
      "fcdd9f96dc44bc1b813d478725911054948da20e4d929282b35722c28924577c",
      evidence.fetch("sha256")
    )
    assert_equal(
      %w[inline-license-notice attribution],
      evidence.fetch("evidenceKinds")
    )
  end

  def test_pins_enabled_busybox_logger_inline_notice
    source = @candidate.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    review_source = @review.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    evidence = review_source.fetch("candidateEvidence").find do |candidate|
      candidate.fetch("outputPath") == "evidence/busybox/sysklogd-logger.c"
    end

    assert_includes(
      source.fetch("existingEvidencePaths"),
      "evidence/busybox/sysklogd-logger.c"
    )
    assert_includes(
      source.fetch("supplementalAportsPaths"),
      "aports/busybox/busyboxconfig"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "confirm-enabled-logger-license-and-attribution-coverage"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "review-other-bundled-third-party-license-and-attribution-coverage"
    )
    assert_equal "busybox-1.36.1/sysklogd/logger.c", evidence.fetch("member")
    assert_equal 5_529, evidence.fetch("byteCount")
    assert_equal(
      "77d22f4c54824cd8bc8ede513693d9f4eb6977302908daac3797f3ee4573e611",
      evidence.fetch("sha256")
    )
    assert_equal(
      %w[inline-license-notice attribution],
      evidence.fetch("evidenceKinds")
    )
  end

  def test_pins_enabled_busybox_cal_inline_notice
    source = @candidate.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    review_source = @review.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    evidence = review_source.fetch("candidateEvidence").find do |candidate|
      candidate.fetch("outputPath") == "evidence/busybox/util-linux-cal.c"
    end

    assert_includes(
      source.fetch("existingEvidencePaths"),
      "evidence/busybox/util-linux-cal.c"
    )
    assert_includes(
      source.fetch("supplementalAportsPaths"),
      "aports/busybox/busyboxconfig"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "confirm-enabled-cal-license-and-attribution-coverage"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "review-other-bundled-third-party-license-and-attribution-coverage"
    )
    assert_equal "busybox-1.36.1/util-linux/cal.c", evidence.fetch("member")
    assert_equal 10_951, evidence.fetch("byteCount")
    assert_equal(
      "39798fa68229dcb25817d906ac1990cc147fd84065918a1404b56263d7a6e311",
      evidence.fetch("sha256")
    )
    assert_equal(
      %w[inline-license-notice attribution],
      evidence.fetch("evidenceKinds")
    )
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
    payload = @candidate.fetch("remotePayloads").find do |candidate|
      candidate["sourceOrigin"] == "openssl"
    end
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
