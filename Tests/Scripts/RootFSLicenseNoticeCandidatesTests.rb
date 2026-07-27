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
    assert_equal 78, validated.fetch(:existing_evidence_paths).length
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

  def test_pins_enabled_busybox_ping_and_ping6_inline_notice
    source = @candidate.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    review_source = @review.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    evidence = review_source.fetch("candidateEvidence").find do |candidate|
      candidate.fetch("outputPath") == "evidence/busybox/networking-ping.c"
    end

    assert_includes(
      source.fetch("existingEvidencePaths"),
      "evidence/busybox/networking-ping.c"
    )
    assert_includes(
      source.fetch("supplementalAportsPaths"),
      "aports/busybox/busyboxconfig"
    )
    assert_includes(
      source.fetch("supplementalAportsPaths"),
      "aports/busybox/0016-ping-make-ping-work-without-root-privileges.patch"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "confirm-enabled-ping-and-ping6-license-and-attribution-coverage"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "review-other-bundled-third-party-license-and-attribution-coverage"
    )
    assert_equal "busybox-1.36.1/networking/ping.c", evidence.fetch("member")
    assert_equal 31_080, evidence.fetch("byteCount")
    assert_equal(
      "f5500d03eb8c681589cd99a861ce57bec208bfdded726b5529c61967e738a205",
      evidence.fetch("sha256")
    )
    assert_equal(
      %w[inline-license-notice attribution],
      evidence.fetch("evidenceKinds")
    )
  end

  def test_pins_enabled_busybox_traceroute_and_traceroute6_inline_notice
    source = @candidate.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    review_source = @review.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    evidence = review_source.fetch("candidateEvidence").find do |candidate|
      candidate.fetch("outputPath") ==
        "evidence/busybox/networking-traceroute.c"
    end

    assert_includes(
      source.fetch("existingEvidencePaths"),
      "evidence/busybox/networking-traceroute.c"
    )
    assert_includes(
      source.fetch("supplementalAportsPaths"),
      "aports/busybox/busyboxconfig"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "confirm-enabled-traceroute-and-traceroute6-license-and-attribution-coverage"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "review-other-bundled-third-party-license-and-attribution-coverage"
    )
    assert_equal(
      "busybox-1.36.1/networking/traceroute.c",
      evidence.fetch("member")
    )
    assert_equal 40_524, evidence.fetch("byteCount")
    assert_equal(
      "c75965e8ad6670e92ed1c4c116141a51cb78d77e3e47286e4527514bf8b1c229",
      evidence.fetch("sha256")
    )
    assert_equal(
      %w[inline-license-notice attribution],
      evidence.fetch("evidenceKinds")
    )
  end

  def test_pins_enabled_busybox_od_hexdump_and_hd_notices
    source = @candidate.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    review_source = @review.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    expected = {
      "evidence/busybox/coreutils-od.c" => {
        member: "busybox-1.36.1/coreutils/od.c",
        bytes: 6_634,
        sha256: "8536f85598a87c49db70a583d9c40004719e64b4939e1d58bcbe30e1e8c5417a",
        kinds: %w[inline-license-notice attribution]
      },
      "evidence/busybox/coreutils-od_bloaty.c" => {
        member: "busybox-1.36.1/coreutils/od_bloaty.c",
        bytes: 37_473,
        sha256: "eb4ae669c359554eac9dcbac2f7625fb5413b34a76ded366a1ec13e47a729b62",
        kinds: %w[license-declaration attribution]
      },
      "evidence/busybox/util-linux-hexdump.c" => {
        member: "busybox-1.36.1/util-linux/hexdump.c",
        bytes: 4_392,
        sha256: "97e49fc1c02560fd65443a7eafbcfbeab44267f3146e0efa1738ae902d69de84",
        kinds: %w[license-declaration attribution]
      },
      "evidence/busybox/libbb-dump.c" => {
        member: "busybox-1.36.1/libbb/dump.c",
        bytes: 22_017,
        sha256: "a1c705a48bd6eb43b4cb9cfb74d61f47f8500b601ebd9d3502906093f7c8ddfe",
        kinds: %w[inline-license-notice attribution]
      }
    }

    expected.each do |output_path, values|
      evidence = review_source.fetch("candidateEvidence").find do |candidate|
        candidate.fetch("outputPath") == output_path
      end

      assert_includes source.fetch("existingEvidencePaths"), output_path
      assert_equal values.fetch(:member), evidence.fetch("member")
      assert_equal values.fetch(:bytes), evidence.fetch("byteCount")
      assert_equal values.fetch(:sha256), evidence.fetch("sha256")
      assert_equal values.fetch(:kinds), evidence.fetch("evidenceKinds")
    end
    assert_includes(
      source.fetch("supplementalAportsPaths"),
      "aports/busybox/busyboxconfig"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "confirm-enabled-od-hexdump-and-hd-license-and-attribution-coverage"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "review-other-bundled-third-party-license-and-attribution-coverage"
    )
  end

  def test_pins_enabled_busybox_expand_unexpand_and_fold_notices
    source = @candidate.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    review_source = @review.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    expected = {
      "evidence/busybox/coreutils-expand.c" => {
        member: "busybox-1.36.1/coreutils/expand.c",
        bytes: 6_393,
        sha256: "66296875f04016bba0721d4fa80393317ffca014e4b4722ed8e7e7fb1c882802"
      },
      "evidence/busybox/coreutils-fold.c" => {
        member: "busybox-1.36.1/coreutils/fold.c",
        bytes: 5_018,
        sha256: "db291cf01ee9a90244607c88a5d88ddf7d2600237eca6f2d7a6894815928cdef"
      }
    }

    expected.each do |output_path, values|
      evidence = review_source.fetch("candidateEvidence").find do |candidate|
        candidate.fetch("outputPath") == output_path
      end

      assert_includes source.fetch("existingEvidencePaths"), output_path
      assert_equal values.fetch(:member), evidence.fetch("member")
      assert_equal values.fetch(:bytes), evidence.fetch("byteCount")
      assert_equal values.fetch(:sha256), evidence.fetch("sha256")
      assert_equal(
        %w[license-declaration attribution],
        evidence.fetch("evidenceKinds")
      )
    end
    assert_includes(
      source.fetch("supplementalAportsPaths"),
      "aports/busybox/busyboxconfig"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "confirm-enabled-expand-unexpand-and-fold-license-and-attribution-coverage"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "review-other-bundled-third-party-license-and-attribution-coverage"
    )
  end

  def test_pins_enabled_busybox_cut_sort_and_uniq_notices
    source = @candidate.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    review_source = @review.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    expected = {
      "evidence/busybox/coreutils-cut.c" => {
        member: "busybox-1.36.1/coreutils/cut.c",
        bytes: 9_783,
        sha256: "bfae86e174a6c51c7fbfee90fd8a5e2901286940378e576e141690bfa55dcc1a"
      },
      "evidence/busybox/coreutils-sort.c" => {
        member: "busybox-1.36.1/coreutils/sort.c",
        bytes: 18_817,
        sha256: "cb92adb0e734b63ae5312a157a9a735cab44bbda4cfd01c52d556be22eca5ff0"
      },
      "evidence/busybox/coreutils-uniq.c" => {
        member: "busybox-1.36.1/coreutils/uniq.c",
        bytes: 3_681,
        sha256: "09c15b3e70e0b5ac2e65b42b1e556f9b25199b846b2ac75dc730d18650d14f7d"
      }
    }

    expected.each do |output_path, values|
      evidence = review_source.fetch("candidateEvidence").find do |candidate|
        candidate.fetch("outputPath") == output_path
      end

      assert_includes source.fetch("existingEvidencePaths"), output_path
      assert_equal values.fetch(:member), evidence.fetch("member")
      assert_equal values.fetch(:bytes), evidence.fetch("byteCount")
      assert_equal values.fetch(:sha256), evidence.fetch("sha256")
      assert_equal(
        %w[license-declaration attribution],
        evidence.fetch("evidenceKinds")
      )
    end
    assert_includes(
      source.fetch("supplementalAportsPaths"),
      "aports/busybox/busyboxconfig"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "confirm-enabled-cut-sort-and-uniq-license-and-attribution-coverage"
    )
    assert_includes(
      source.fetch("remainingReviewItems"),
      "review-other-bundled-third-party-license-and-attribution-coverage"
    )
  end

  def test_pins_remaining_busybox_build_closure_notices
    source = @candidate.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    review_source = @review.fetch("sources").find do |candidate|
      candidate.fetch("sourceOrigin") == "busybox"
    end
    relative_paths = %w[
      archival/bbunzip.c
      archival/libarchive/decompress_gunzip.c
      archival/libarchive/liblzo.h
      archival/libarchive/lzo1x_1.c
      archival/libarchive/lzo1x_1o.c
      archival/libarchive/lzo1x_c.c
      archival/libarchive/lzo1x_d.c
      archival/libarchive/unxz/xz.h
      archival/libarchive/unxz/xz_config.h
      archival/libarchive/unxz/xz_dec_bcj.c
      archival/libarchive/unxz/xz_dec_lzma2.c
      archival/libarchive/unxz/xz_dec_stream.c
      archival/libarchive/unxz/xz_lzma2.h
      archival/libarchive/unxz/xz_private.h
      archival/libarchive/unxz/xz_stream.h
      archival/lzop.c
      coreutils/dos2unix.c
      coreutils/sync.c
      coreutils/test.c
      coreutils/tr.c
      include/liblzo_interface.h
      libbb/change_identity.c
      libbb/correct_password.c
      libbb/hash_md5_sha.c
      libbb/procps.c
      libbb/progress.c
      libbb/pw_encrypt_des.c
      libbb/pw_encrypt_sha.c
      libbb/run_shell.c
      libbb/setup_environment.c
      libbb/vfork_daemon_rexec.c
      libpwdgrp/uidgid_get.c
      loginutils/add-remove-shell.c
      miscutils/bbconfig.c
      networking/nc_bloaty.c
      procps/pmap.c
      shell/ash.c
      shell/shell_common.c
      shell/shell_common.h
      util-linux/fdisk_osf.c
      util-linux/setsid.c
    ]
    evidence = review_source.fetch("candidateEvidence").select do |candidate|
      candidate.fetch("outputPath").start_with?(
        "evidence/busybox/build-closure-"
      )
    end

    assert_equal 41, evidence.length
    assert_equal(
      relative_paths.map { |path| "busybox-1.36.1/#{path}" },
      evidence.map { |candidate| candidate.fetch("member") }
    )
    evidence.zip(relative_paths).each do |candidate, relative_path|
      expected_output =
        "evidence/busybox/build-closure-#{relative_path.tr("/", "-")}"

      assert_equal expected_output, candidate.fetch("outputPath")
      assert_operator candidate.fetch("byteCount"), :>, 0
      assert_match(/\A[0-9a-f]{64}\z/, candidate.fetch("sha256"))
      assert_equal(
        %w[inline-license-notice attribution],
        candidate.fetch("evidenceKinds")
      )
      assert_includes source.fetch("existingEvidencePaths"), expected_output
    end
    assert_includes(
      source.fetch("remainingReviewItems"),
      "review-other-bundled-third-party-license-and-attribution-coverage"
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
