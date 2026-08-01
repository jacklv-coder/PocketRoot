#!/usr/bin/env ruby

require "fileutils"
require "json"
require "minitest/autorun"
require "pathname"
require "tmpdir"
require_relative "../../Scripts/generate-release-compliance"

class ReleaseComplianceTests < Minitest::Test
  REPOSITORY_ROOT = Pathname(__dir__).join("../..").realpath
  INPUT_PATHS = [
    "LICENSE",
    "NOTICE.md",
    "CONTRIBUTING.md",
    "CONTRIBUTING.en.md",
    "Compliance/SPDX/LICENSE-LIST-3.28.0.json",
    "Compliance/Release/RELEASE-DECISIONS.json",
    "Package.resolved",
    "Package.swift",
    "Examples/PocketRootDemo/project.yml",
    "Examples/PocketRootHostApp/project.yml",
    "Examples/PocketRootQuickStartApp/project.yml",
    "Tests/Integration/ExternalConsumerApp/project.yml.template",
    "Scripts/inject-demo-rootfs.sh",
    "Scripts/scan-release-artifact.rb",
    "Scripts/run-host-app-device-ui-smoke.sh",
    "Scripts/run-host-app-ui-smoke.sh",
    "Scripts/run-ios-example-ui-smoke.sh",
    "Scripts/run-quick-start-ui-smoke.sh",
    "Scripts/run-external-consumer-ui-smoke.sh",
    "ThirdPartyNotices/SwiftTerm-LICENSE.txt",
    "Compliance/RootFS/v0.3.3/EVIDENCE.json",
    "Compliance/RootFS/v0.3.3/SBOM.spdx.json"
  ].freeze

  def setup
    @temporary_directory =
      Pathname(Dir.mktmpdir("pocketroot-release-compliance-test-"))
  end

  def teardown
    FileUtils.remove_entry(@temporary_directory) if @temporary_directory.exist?
  end

  def test_checked_in_outputs_are_reproducible
    assert PocketRootReleaseCompliance.check
  end

  def test_json_formatting_is_independent_of_json_gem_pretty_defaults
    document = {
      "emptyArray" => [],
      "emptyObject" => {},
      "nested" => [
        {"value" => "line\n\t\"\\\u0001雪"}
      ],
      "flag" => false,
      "count" => 7,
      "fraction" => 1.25,
      "exponent" => 1.0e+20,
      "negativeZero" => -0.0,
      "nothing" => nil
    }
    expected = <<~'JSON'
      {
        "emptyArray": [],
        "emptyObject": {},
        "nested": [
          {
            "value": "line\n\t\"\\\u0001雪"
          }
        ],
        "flag": false,
        "count": 7,
        "fraction": 1.25,
        "exponent": 1.0e+20,
        "negativeZero": -0.0,
        "nothing": null
      }
    JSON

    rendered = PocketRootReleaseCompliance.pretty_json(document)

    assert_equal expected, rendered
    assert_equal document, JSON.parse(rendered)
  end

  def test_json_formatting_rejects_non_finite_numbers
    [Float::NAN, Float::INFINITY, -Float::INFINITY].each do |number|
      error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
        PocketRootReleaseCompliance.pretty_json({"number" => number})
      end

      assert_includes error.message, "must be finite"
    end
  end

  def test_full_graph_has_exact_packages_relationships_and_closed_gates
    outputs = PocketRootReleaseCompliance.build_outputs
    composition = JSON.parse(outputs.fetch("COMPOSITION.json"))
    readiness = JSON.parse(outputs.fetch("READINESS.json"))
    sbom = JSON.parse(outputs.fetch("SBOM.spdx.json"))

    assert_equal(
      PocketRootReleaseCompliance::OUTPUT_FILENAMES.sort,
      outputs.keys.sort
    )
    assert_equal 24, sbom.fetch("packages").length
    pocketroot_package = sbom.fetch("packages").find do |package|
      package.fetch("SPDXID") == "SPDXRef-Package-PocketRoot"
    end
    assert_equal "MIT", pocketroot_package.fetch("licenseDeclared")
    %w[LICENSE NOTICE.md CONTRIBUTING.md CONTRIBUTING.en.md].each do |path|
      assert_match(
        /\A[0-9a-f]{64}\z/,
        composition.fetch("repositoryEvidence").fetch(path)
      )
    end
    assert_equal(
      "dd2fb8ac5b861e7bf617c872895e338f38165648",
      composition.dig("externalComponents", "swiftTerm", "revision")
    )
    assert composition.dig(
      "externalComponents",
      "swiftArgumentParser",
      "resolvedOnly"
    )
    rootfs_package = sbom.fetch("packages").find do |package|
      package.fetch("SPDXID") == "SPDXRef-Package-External-RootFS"
    end
    assert_equal(
      "OPERATING_SYSTEM",
      rootfs_package.fetch("primaryPackagePurpose")
    )
    assert_equal 15, sbom.fetch("relationships").count { |relationship|
      relationship["spdxElementId"] ==
        "SPDXRef-Package-External-RootFS" &&
        relationship["relationshipType"] == "CONTAINS"
    }
    assert composition.dig("coverage", "releaseCompositionSBOMGenerated")
    refute composition.dig("coverage", "completeReleaseArtifactSBOM")
    refute composition.dig("coverage", "distributionAuthorized")
    assert_equal "blocked", readiness.fetch("overallStatus")
    assert_equal(
      "rootfs-external-input-boundary",
      readiness.dig("nextRequiredDecision", "id")
    )
  end

  def test_release_readiness_has_independent_fail_closed_tracks
    outputs = PocketRootReleaseCompliance.build_outputs
    readiness = JSON.parse(outputs.fetch("READINESS.json"))
    source = readiness.dig("tracks", "sourcePackageRelease")
    runtime = readiness.dig("tracks", "runtimeDistribution")

    assert_equal "ready", source.fetch("status")
    assert_equal "blocked", runtime.fetch("status")
    assert_includes runtime.fetch("scope"), "excludes every RootFS asset"
    assert_equal(
      [true, true, true, true, true, true],
      source.fetch("gates").map { |gate| gate.fetch("satisfied") }
    )
    assert_equal(
      [true, false, false, false, false, false, false, false, false],
      runtime.fetch("gates").map { |gate| gate.fetch("satisfied") }
    )
    assert_includes(
      readiness.fetch("warning"),
      "source track would not authorize runtime"
    )
    assert_equal(
      runtime.fetch("gates").drop(1).map { |gate| gate.fetch("id") },
      readiness.fetch("blockedGateIds")
    )
  end

  def test_current_engineering_evidence_cannot_make_runtime_ready
    root = input_fixture
    write_final_artifact_evidence(root)
    outputs = PocketRootReleaseCompliance.build_outputs(root)
    composition = JSON.parse(outputs.fetch("COMPOSITION.json"))
    decisions =
      JSON.parse(
        root
          .join("Compliance/Release/RELEASE-DECISIONS.json")
          .binread
      )
    %w[
      releaseArtifactBuilt
      releaseArtifactScanned
      binaryFilesAnalyzed
      completeReleaseArtifactSBOM
      completeLicenseAndNoticeBundle
      correspondingSourceDeliveryApproved
      appStorePolicyApproved
      legalReviewApproved
      distributionAuthorized
      topLevelLicenseFinalized
    ].each do |key|
      composition.fetch("coverage")[key] = true
    end
    decisions["status"] = "source-and-runtime-distribution-authorized"
    decisions.fetch("sourceRelease")["topLevelLicenseSpdx"] = "MIT"
    runtime_decisions = decisions.fetch("runtimeDistribution")
    runtime_decisions["finalArtifactSha256"] =
      composition.dig("finalArtifactEvidence", "artifactSha256")
    %w[
      completeLicenseAndNoticeBundleApproved
      correspondingSourceDeliveryApproved
      appStorePolicyApproved
      privacyReviewApproved
      legalReviewApproved
      distributionAuthorized
    ].each do |key|
      runtime_decisions[key] = true
    end
    approval = decisions.fetch("approval")
    approval["approvedBy"] = "project-owner"
    approval["approvedAt"] = "2026-07-31T12:00:00Z"
    approval["notes"] = "Reviewed RootFS-excluding runtime authorization."

    assert PocketRootReleaseCompliance.validate_release_decisions(
      decisions,
      spdx_license_list
    )
    readiness =
      PocketRootReleaseCompliance.readiness(
        composition,
        {release_decisions: decisions}
      )

    assert PocketRootReleaseCompliance.validate_readiness(readiness)
    evidence = composition.fetch("finalArtifactEvidence")
    assert_equal "engineering-evidence-only", evidence.fetch("status")
    refute evidence.fetch("releaseSignatureValid")
    refute evidence.fetch("rootFSExcluded")
    runtime = readiness.dig("tracks", "runtimeDistribution")
    assert_equal "blocked", runtime.fetch("status")
    assert_includes runtime.fetch("scope"), "excludes every RootFS asset"
    assert runtime.fetch("gates").find { |gate|
      gate.fetch("id") == "runtime-top-level-license-finalized"
    }.fetch("satisfied")
    %w[
      rootfs-external-input-boundary
      release-artifact-built-and-scanned
    ].each do |gate_id|
      refute runtime.fetch("gates").find { |gate|
        gate.fetch("id") == gate_id
      }.fetch("satisfied")
    end
  end

  def test_release_readme_reports_imported_engineering_evidence
    root = input_fixture
    write_final_artifact_evidence(root)

    readme =
      PocketRootReleaseCompliance.build_outputs(root).fetch("README.md")

    assert_includes readme, "状态保持\n`engineering-evidence-only`"
    assert_includes readme,
      "current final-artifact directory contains engineering scan evidence"
    assert_includes readme, "`releaseSignatureValid=false`"
    refute_includes readme, "finalArtifactEvidence.status=not-provided"
    refute_includes readme, "Because no final archive was scanned"
  end

  def test_current_schema_rejects_synthetic_release_artifact_approval
    root = input_fixture
    write_final_artifact_evidence(root)
    inputs = PocketRootReleaseCompliance.collect_inputs(root)
    summary = inputs.fetch(:final_artifact_evidence)
    summary["status"] = "release-signature-validated"
    summary["releaseSignatureValid"] = true
    summary["rootFSExcluded"] = true

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.validate_final_artifact_evidence(
        summary,
        inputs.fetch(:file_sha256)
      )
    end

    assert_includes error.message, "unsupported status"
  end

  def test_runtime_readiness_binds_future_evidence_to_reviewed_artifact_hash
    root = input_fixture
    write_final_artifact_evidence(root)
    outputs = PocketRootReleaseCompliance.build_outputs(root)
    composition = JSON.parse(outputs.fetch("COMPOSITION.json"))
    evidence = composition.fetch("finalArtifactEvidence")
    evidence["releaseSignatureValid"] = true
    evidence["rootFSExcluded"] = true
    runtime_ready_coverage.each do |key|
      composition.fetch("coverage")[key] = true
    end
    matching_decisions =
      reviewed_runtime_authorization_decisions(
        artifact_sha256: evidence.fetch("artifactSha256")
      )

    matching_readiness =
      PocketRootReleaseCompliance.readiness(
        composition,
        {release_decisions: matching_decisions}
      )

    assert_equal(
      "ready",
      matching_readiness.dig("tracks", "runtimeDistribution", "status")
    )

    mismatched_decisions =
      reviewed_runtime_authorization_decisions(
        artifact_sha256: "f" * 64
      )
    mismatched_readiness =
      PocketRootReleaseCompliance.readiness(
        composition,
        {release_decisions: mismatched_decisions}
      )
    runtime = mismatched_readiness.dig("tracks", "runtimeDistribution")

    assert_equal "blocked", runtime.fetch("status")
    %w[
      rootfs-external-input-boundary
      release-artifact-built-and-scanned
    ].each do |gate_id|
      refute runtime.fetch("gates").find { |gate|
        gate.fetch("id") == gate_id
      }.fetch("satisfied")
    end
  end

  def test_runtime_track_rejects_final_artifact_containing_rootfs
    root = input_fixture
    write_final_artifact_evidence(root, include_rootfs: true)
    composition =
      JSON.parse(
        PocketRootReleaseCompliance
          .build_outputs(root)
          .fetch("COMPOSITION.json")
      )
    evidence = composition.fetch("finalArtifactEvidence")
    decisions =
      reviewed_runtime_authorization_decisions(
        artifact_sha256: evidence.fetch("artifactSha256")
      )
    runtime_ready_coverage.each do |key|
      composition.fetch("coverage")[key] = true
    end

    readiness =
      PocketRootReleaseCompliance.readiness(
        composition,
        {release_decisions: decisions}
      )

    assert PocketRootReleaseCompliance.validate_readiness(readiness)
    refute evidence.fetch("rootFSExcluded")
    assert_includes evidence.fetch("rootFSAssetPaths"), "Resources/fs.tar.gz"
    runtime = readiness.dig("tracks", "runtimeDistribution")
    assert_equal "blocked", runtime.fetch("status")
    refute runtime.fetch("gates").find { |gate|
      gate.fetch("id") == "rootfs-external-input-boundary"
    }.fetch("satisfied")
  end

  def test_rootfs_boundary_rejects_repacked_project_archive
    inventory = {
      "directories" => [
        {"path" => "Resources", "mode" => "0755"},
        {"path" => "Resources/alpine-rootfs-v0.3.3", "mode" => "0755"}
      ],
      "files" => [
        {
          "path" => "Resources/pocketroot-fs-v0.4.0.tar.gz",
          "byteCount" => 1234,
          "sha256" => "f" * 64
        },
        {
          "path" => "Resources/rootfs",
          "byteCount" => 4321,
          "sha256" => "e" * 64
        },
        {
          "path" => "Resources/alpine-rootfs-v0.3.3/bin/sh",
          "byteCount" => 9876,
          "sha256" => "d" * 64
        }
      ]
    }

    assert_equal(
      [
        "Resources/alpine-rootfs-v0.3.3",
        "Resources/alpine-rootfs-v0.3.3/bin/sh",
        "Resources/pocketroot-fs-v0.4.0.tar.gz",
        "Resources/rootfs"
      ],
      PocketRootReleaseCompliance.final_artifact_rootfs_asset_paths(
        inventory
      )
    )
  end

  def test_runtime_track_rejects_nested_development_entitlement
    root = input_fixture
    write_final_artifact_evidence(
      root,
      binary_get_task_allow: true
    )

    composition =
      JSON.parse(
        PocketRootReleaseCompliance
          .build_outputs(root)
          .fetch("COMPOSITION.json")
      )
    evidence = composition.fetch("finalArtifactEvidence")

    assert_equal "engineering-evidence-only", evidence.fetch("status")
    refute evidence.fetch("releaseSignatureValid")
  end

  def test_runtime_track_rejects_non_boolean_nested_debug_entitlement
    ["true", 1].each do |value|
      root = input_fixture("nested-entitlement-#{value.class}")
      write_final_artifact_evidence(
        root,
        binary_get_task_allow: value
      )

      composition =
        JSON.parse(
          PocketRootReleaseCompliance
            .build_outputs(root)
            .fetch("COMPOSITION.json")
        )
      evidence = composition.fetch("finalArtifactEvidence")

      assert_equal "engineering-evidence-only", evidence.fetch("status")
      refute evidence.fetch("releaseSignatureValid")
    end
  end

  def test_runtime_track_rejects_incomplete_mach_o_inventory
    root = input_fixture
    write_final_artifact_evidence(
      root,
      omit_nested_mach_o: true
    )

    error =
      assert_raises(PocketRootReleaseCompliance::ComplianceError) do
        PocketRootReleaseCompliance.build_outputs(root)
      end

    assert_includes error.message,
      "final artifact evidence failed scanner validation"
    assert_includes error.message, "Mach-O inventory coverage is incomplete"
  end

  def test_runtime_track_rejects_unsigned_final_artifact_evidence
    root = input_fixture
    write_final_artifact_evidence(root, release_signed: false)
    composition =
      JSON.parse(
        PocketRootReleaseCompliance
          .build_outputs(root)
          .fetch("COMPOSITION.json")
      )
    evidence = composition.fetch("finalArtifactEvidence")
    decisions =
      reviewed_runtime_authorization_decisions(
        artifact_sha256: evidence.fetch("artifactSha256")
      )
    runtime_ready_coverage.each do |key|
      composition.fetch("coverage")[key] = true
    end

    readiness =
      PocketRootReleaseCompliance.readiness(
        composition,
        {release_decisions: decisions}
      )

    assert_equal "engineering-evidence-only", evidence.fetch("status")
    refute evidence.fetch("releaseSignatureValid")
    runtime = readiness.dig("tracks", "runtimeDistribution")
    assert_equal "blocked", runtime.fetch("status")
    %w[
      rootfs-external-input-boundary
      release-artifact-built-and-scanned
    ].each do |gate_id|
      refute runtime.fetch("gates").find { |gate|
        gate.fetch("id") == gate_id
      }.fetch("satisfied")
    end
  end

  def test_runtime_track_rejects_unreviewed_final_artifact_identity
    root = input_fixture
    write_final_artifact_evidence(root)
    composition =
      JSON.parse(
        PocketRootReleaseCompliance
          .build_outputs(root)
          .fetch("COMPOSITION.json")
      )
    decisions =
      reviewed_runtime_authorization_decisions(
        artifact_sha256: "f" * 64
      )
    runtime_ready_coverage.each do |key|
      composition.fetch("coverage")[key] = true
    end

    readiness =
      PocketRootReleaseCompliance.readiness(
        composition,
        {release_decisions: decisions}
      )

    assert PocketRootReleaseCompliance.validate_readiness(readiness)
    runtime = readiness.dig("tracks", "runtimeDistribution")
    assert_equal "blocked", runtime.fetch("status")
    %w[
      rootfs-external-input-boundary
      release-artifact-built-and-scanned
    ].each do |gate_id|
      refute runtime.fetch("gates").find { |gate|
        gate.fetch("id") == gate_id
      }.fetch("satisfied")
    end
  end

  def test_runtime_track_rejects_unfinalized_top_level_license
    root = input_fixture
    write_final_artifact_evidence(root)
    composition =
      JSON.parse(
        PocketRootReleaseCompliance
          .build_outputs(root)
          .fetch("COMPOSITION.json")
      )
    decisions =
      reviewed_runtime_authorization_decisions(
        artifact_sha256:
          composition.dig("finalArtifactEvidence", "artifactSha256")
      )
    (runtime_ready_coverage - ["topLevelLicenseFinalized"]).each do |key|
      composition.fetch("coverage")[key] = true
    end
    composition.fetch("coverage")["topLevelLicenseFinalized"] = false

    readiness =
      PocketRootReleaseCompliance.readiness(
        composition,
        {release_decisions: decisions}
      )

    assert PocketRootReleaseCompliance.validate_readiness(readiness)
    runtime = readiness.dig("tracks", "runtimeDistribution")
    assert_equal "blocked", runtime.fetch("status")
    refute runtime.fetch("gates").find { |gate|
      gate.fetch("id") == "runtime-top-level-license-finalized"
    }.fetch("satisfied")
  end

  def test_readiness_validator_allows_source_track_to_become_ready_independently
    outputs = PocketRootReleaseCompliance.build_outputs
    composition = JSON.parse(outputs.fetch("COMPOSITION.json"))
    decisions =
      JSON.parse(
        REPOSITORY_ROOT
          .join("Compliance/Release/RELEASE-DECISIONS.json")
          .binread
      )
    composition.fetch("coverage")["topLevelLicenseFinalized"] = true
    source_decisions = decisions.fetch("sourceRelease")
    source_decisions["topLevelLicenseSpdx"] = "MIT"
    source_decisions["contributorPolicyApproved"] = true
    source_decisions["releaseNoticeApproved"] = true
    source_decisions["sourceReleaseAuthorized"] = true

    readiness =
      PocketRootReleaseCompliance.readiness(
        composition,
        {release_decisions: decisions}
      )

    assert PocketRootReleaseCompliance.validate_readiness(readiness)
    assert_equal(
      "ready",
      readiness.dig("tracks", "sourcePackageRelease", "status")
    )
    assert_equal(
      "blocked",
      readiness.dig("tracks", "runtimeDistribution", "status")
    )
    assert_equal "blocked", readiness.fetch("overallStatus")
    assert_equal(
      "rootfs-external-input-boundary",
      readiness.dig("nextRequiredDecision", "id")
    )
    assert PocketRootReleaseCompliance.require_ready_track(
      readiness,
      "sourcePackageRelease"
    )
  end

  def test_release_checklist_documents_both_tracks_and_enforcement_commands
    checklist =
      PocketRootReleaseCompliance.build_outputs.fetch("RELEASE-CHECKLIST.md")

    assert_includes checklist, "源码与 Swift Package 发布"
    assert_includes checklist, "Runtime / App / 二进制分发（不含 RootFS"
    assert_includes checklist, "Source and Swift Package release"
    assert_includes checklist,
      "Runtime / App / binary distribution (RootFS excluded"
    assert_includes checklist, "--require-source-ready"
    assert_includes checklist, "--require-runtime-ready"
    assert_includes checklist, "项目所有者确定为 MIT"
  end

  def test_release_checklist_reports_independent_track_statuses
    outputs = PocketRootReleaseCompliance.build_outputs
    composition = JSON.parse(outputs.fetch("COMPOSITION.json"))
    decisions =
      JSON.parse(
        REPOSITORY_ROOT
          .join("Compliance/Release/RELEASE-DECISIONS.json")
          .binread
      )
    composition.fetch("coverage")["topLevelLicenseFinalized"] = true
    source = decisions.fetch("sourceRelease")
    source["topLevelLicenseSpdx"] = "MIT"
    source["contributorPolicyApproved"] = true
    source["releaseNoticeApproved"] = true
    source["sourceReleaseAuthorized"] = true
    readiness =
      PocketRootReleaseCompliance.readiness(
        composition,
        {release_decisions: decisions}
      )

    checklist = PocketRootReleaseCompliance.release_checklist(readiness)

    assert_includes checklist, "当前状态：**Blocked / 不可发布**"
    assert_includes checklist,
      "源码与 Swift Package 发布（Ready / 已就绪）"
    assert_includes checklist,
      "Runtime / App / 二进制分发（不含 RootFS，Blocked / 未就绪）"
    assert_includes checklist, "Source and Swift Package release (Ready)"
    assert_includes checklist,
      "Runtime / App / binary distribution (RootFS excluded, Blocked)"
  end

  def test_release_decisions_reject_unreviewed_authorization
    decisions =
      JSON.parse(
        REPOSITORY_ROOT
          .join("Compliance/Release/RELEASE-DECISIONS.json")
          .binread
      )
    decisions.fetch("runtimeDistribution")["distributionAuthorized"] = true

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.validate_release_decisions(
        decisions,
        spdx_license_list
      )
    end

    assert_includes error.message, "fail-closed invariants"
  end

  def test_release_decisions_accept_reviewed_source_authorization
    decisions =
      JSON.parse(
        REPOSITORY_ROOT
          .join("Compliance/Release/RELEASE-DECISIONS.json")
          .binread
      )
    decisions["status"] = "source-release-authorized"
    source = decisions.fetch("sourceRelease")
    source["topLevelLicenseSpdx"] = "MIT"
    source["contributorPolicyApproved"] = true
    source["releaseNoticeApproved"] = true
    source["sourceReleaseAuthorized"] = true
    approval = decisions.fetch("approval")
    approval["approvedBy"] = "project-owner"
    approval["approvedAt"] = "2026-07-31T12:00:00Z"
    approval["notes"] = "Reviewed source-release authorization."

    assert PocketRootReleaseCompliance.validate_release_decisions(
      decisions,
      spdx_license_list
    )
  end

  def test_release_decisions_accept_reviewed_runtime_authorization
    decisions =
      JSON.parse(
        REPOSITORY_ROOT
          .join("Compliance/Release/RELEASE-DECISIONS.json")
          .binread
      )
    decisions["status"] = "source-and-runtime-distribution-authorized"
    decisions.fetch("sourceRelease")["topLevelLicenseSpdx"] = "MIT"
    runtime = decisions.fetch("runtimeDistribution")
    runtime["finalArtifactSha256"] = "a" * 64
    runtime["completeLicenseAndNoticeBundleApproved"] = true
    runtime["correspondingSourceDeliveryApproved"] = true
    runtime["appStorePolicyApproved"] = true
    runtime["privacyReviewApproved"] = true
    runtime["legalReviewApproved"] = true
    runtime["distributionAuthorized"] = true
    approval = decisions.fetch("approval")
    approval["approvedBy"] = "project-owner"
    approval["approvedAt"] = "2026-07-31T12:00:00Z"
    approval["notes"] = "Reviewed runtime-distribution authorization."

    assert PocketRootReleaseCompliance.validate_release_decisions(
      decisions,
      spdx_license_list
    )
  end

  def test_release_decisions_reject_runtime_authorization_without_license
    decisions =
      reviewed_runtime_authorization_decisions
    decisions.fetch("sourceRelease")["topLevelLicenseSpdx"] = nil

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.validate_release_decisions(
        decisions,
        spdx_license_list
      )
    end

    assert_includes error.message, "fail-closed invariants"
  end

  def test_release_decisions_reject_runtime_authorization_without_artifact_hash
    decisions =
      reviewed_runtime_authorization_decisions
    decisions.fetch("runtimeDistribution")["finalArtifactSha256"] = nil

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.validate_release_decisions(
        decisions,
        spdx_license_list
      )
    end

    assert_includes error.message, "fail-closed invariants"
  end

  def test_release_decisions_reject_invalid_final_artifact_hash
    decisions =
      JSON.parse(
        REPOSITORY_ROOT
          .join("Compliance/Release/RELEASE-DECISIONS.json")
          .binread
      )
    decisions.fetch("runtimeDistribution")["finalArtifactSha256"] =
      "not-a-sha256"
    approval = decisions.fetch("approval")
    approval["approvedBy"] = "project-owner"
    approval["approvedAt"] = "2026-07-31T12:00:00Z"

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.validate_release_decisions(
        decisions,
        spdx_license_list
      )
    end

    assert_includes error.message, "fail-closed invariants"
  end

  def test_release_decisions_reject_invalid_spdx_expression
    decisions =
      JSON.parse(
        REPOSITORY_ROOT
          .join("Compliance/Release/RELEASE-DECISIONS.json")
          .binread
      )
    decisions["status"] = "source-release-authorized"
    source = decisions.fetch("sourceRelease")
    source["topLevelLicenseSpdx"] = "definitely-not-an-spdx-license"
    source["contributorPolicyApproved"] = true
    source["releaseNoticeApproved"] = true
    source["sourceReleaseAuthorized"] = true
    approval = decisions.fetch("approval")
    approval["approvedBy"] = "project-owner"
    approval["approvedAt"] = "2026-07-31T12:00:00Z"
    approval["notes"] = "Invalid license value must fail closed."

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.validate_release_decisions(
        decisions,
        spdx_license_list
      )
    end

    assert_includes error.message, "fail-closed invariants"
  end

  def test_spdx_expression_accepts_pinned_ids_operators_and_exception
    expression =
      "(MIT OR Apache-2.0) AND " \
      "(GPL-2.0-only WITH Classpath-exception-2.0)"

    assert PocketRootReleaseCompliance.valid_spdx_license_expression?(
      expression,
      spdx_license_list
    )
    refute PocketRootReleaseCompliance.valid_spdx_license_expression?(
      "MIT WITH definitely-not-an-spdx-exception",
      spdx_license_list
    )
    refute PocketRootReleaseCompliance.valid_spdx_license_expression?(
      "(MIT OR Apache-2.0",
      spdx_license_list
    )
  end

  def test_readiness_cli_reports_source_ready_and_runtime_blocked
    status_output, status_error =
      capture_io do
        assert_equal 0, PocketRootReleaseCompliance.execute(["--status"])
      end
    assert_empty status_error
    assert_includes status_output, "release readiness: BLOCKED"
    assert_includes status_output, "sourcePackageRelease: READY"
    assert_includes status_output, "runtimeDistribution: BLOCKED"

    source_output, source_error =
      capture_io do
        assert_equal(
          0,
          PocketRootReleaseCompliance.execute(["--require-source-ready"])
        )
      end
    assert_includes source_output,
      "Source and Swift Package release track is READY."
    assert_empty source_error

    runtime_output, runtime_error =
      capture_io do
        assert_equal(
          2,
          PocketRootReleaseCompliance.execute(["--require-runtime-ready"])
        )
      end
    assert_empty runtime_output
    assert_includes runtime_error, "runtimeDistribution is BLOCKED"
    assert_includes runtime_error, "runtime-distribution-authorized"
  end

  def test_default_demo_links_runtime_but_does_not_bundle_rootfs_by_default
    composition =
      JSON.parse(
        PocketRootReleaseCompliance.build_outputs.fetch("COMPOSITION.json")
      )
    default_profile =
      composition.fetch("profiles").find do |profile|
        profile.fetch("id") == "default-demo"
      end

    assert default_profile.fetch("includesIshRuntime")
    assert default_profile.fetch("requiresExternalRootFS")
    refute composition.dig(
      "externalComponents",
      "rootFS",
      "bundledByDefault"
    )
    refute composition.dig(
      "externalComponents",
      "rootFS",
      "downloadedByLibrary"
    )
  end

  def test_standalone_host_profile_uses_only_public_integration_products
    composition =
      JSON.parse(
        PocketRootReleaseCompliance.build_outputs.fetch("COMPOSITION.json")
      )
    host_profile =
      composition.fetch("profiles").find do |profile|
        profile.fetch("id") == "standalone-host-example"
      end

    assert_equal "PocketRootHostApp", host_profile.fetch("rootTarget")
    assert_equal(
      ["PocketRoot", "PocketRootIshRuntimeIntegration"],
      host_profile.fetch("swiftProducts")
    )
    assert host_profile.fetch("includesIshRuntime")
    assert host_profile.fetch("requiresExternalRootFS")
    refute host_profile.fetch("artifactBuiltAndScanned")
  end

  def test_quick_start_profile_uses_two_public_host_entries
    composition =
      JSON.parse(
        PocketRootReleaseCompliance.build_outputs.fetch("COMPOSITION.json")
      )
    profile =
      composition.fetch("profiles").find do |candidate|
        candidate.fetch("id") == "two-entry-quick-start-example"
      end
    source =
      REPOSITORY_ROOT
        .join("Examples/PocketRootQuickStartApp/Sources/QuickStartApp.swift")
        .binread

    assert_equal "PocketRootQuickStartApp", profile.fetch("rootTarget")
    assert_equal(
      ["PocketRoot", "PocketRootIshRuntimeIntegration"],
      profile.fetch("swiftProducts")
    )
    assert profile.fetch("includesIshRuntime")
    assert profile.fetch("requiresExternalRootFS")
    refute profile.fetch("artifactBuiltAndScanned")
    assert_includes source, "host.makeTerminalViewController()"
    assert_includes source, "host.makeFilesViewController()"
    assert_includes source, "func sceneDidDisconnect(_ scene: UIScene)"
    assert_includes source, "pocketRootHost?.closeWorkspaces()"

    project =
      REPOSITORY_ROOT
        .join("Examples/PocketRootQuickStartApp/project.yml")
        .binread
    ui_test =
      REPOSITORY_ROOT
        .join(
          "Examples/PocketRootQuickStartApp/UITests/" \
          "PocketRootQuickStartAppUITests.swift"
        )
        .binread
    runner =
      REPOSITORY_ROOT
        .join("Scripts/run-quick-start-ui-smoke.sh")
        .binread
    workflow = REPOSITORY_ROOT.join(".github/workflows/ci.yml").binread

    assert_includes project, "PocketRootQuickStartAppUITests:"
    assert_includes project, "type: bundle.ui-testing"
    assert_includes ui_test, "testFilesEntryAutoBootsFromColdLaunch"
    assert_includes ui_test, "testTerminalCreatesFileThatFilesCanPreview"
    assert_includes ui_test, "PocketRootTerminal.pty"
    assert_includes ui_test, "PocketRootFiles.preview"
    assert_includes runner, "run-ios-example-ui-smoke.sh"
    assert_includes workflow, "./Scripts/run-quick-start-ui-smoke.sh"
  end

  def test_external_consumer_profile_resolves_public_products_and_lifecycle
    composition =
      JSON.parse(
        PocketRootReleaseCompliance.build_outputs.fetch("COMPOSITION.json")
      )
    profile =
      composition.fetch("profiles").find do |candidate|
        candidate.fetch("id") == "external-consumer-acceptance"
      end
    fixture_root =
      REPOSITORY_ROOT.join("Tests/Integration/ExternalConsumerApp")
    project = fixture_root.join("project.yml.template").binread
    source =
      fixture_root.join("Sources/ExternalConsumerApp.swift").binread
    ui_test =
      fixture_root.join(
        "UITests/ExternalConsumerAppUITests.swift"
      ).binread
    runner =
      REPOSITORY_ROOT
        .join("Scripts/run-external-consumer-ui-smoke.sh")
        .binread
    workflow = REPOSITORY_ROOT.join(".github/workflows/ci.yml").binread

    assert_equal "PocketRootExternalConsumerApp", profile.fetch("rootTarget")
    assert_equal(
      ["PocketRoot", "PocketRootIshRuntimeIntegration"],
      profile.fetch("swiftProducts")
    )
    assert profile.fetch("includesIshRuntime")
    assert profile.fetch("requiresExternalRootFS")
    refute profile.fetch("artifactBuiltAndScanned")
    assert_includes project, "__POCKETROOT_PACKAGE_SOURCE__"
    assert_includes project, "product: PocketRootIshRuntimeIntegration"
    assert_includes source, "host.makeTerminalViewController()"
    assert_includes source, "host.makeFilesViewController()"
    assert_includes source, "try await host.shutdown()"
    assert_includes ui_test,
      "testRemoteConsumerTerminalFilesAndLifecycleClosure"
    assert_includes ui_test, "XCUIDevice.shared.press(.home)"
    assert_includes ui_test, "app.wait(for: .runningBackground"
    assert_includes ui_test, "app.wait(for: .runningForeground"
    assert_includes ui_test,
      "__POCKETROOT_EXTERNAL_CONSUMER_FOREGROUND__"
    assert_includes ui_test, "Runtime Terminated"
    assert_includes runner, "POCKETROOT_EXTERNAL_CONSUMER_REVISION"
    assert_includes runner,
      "POCKETROOT_EXTERNAL_CONSUMER_REPOSITORY_URL"
    assert_includes workflow,
      "Run public-SHA External Consumer UI acceptance"
  end

  def test_standalone_host_retains_runtime_across_scene_recreation
    source =
      REPOSITORY_ROOT
        .join("Examples/PocketRootHostApp/Sources/HostApp.swift")
        .binread

    assert_match(
      /final class HostAppDelegate:.*?var workspaceHost:/m,
      source
    )
    assert_includes source, "HostViewController(runtimeOwner: appDelegate)"
    assert_includes source, "private unowned let runtimeOwner: HostAppDelegate"
    assert_includes source, "func sceneDidDisconnect(_ scene: UIScene)"
    assert_includes(
      source,
      "hostViewController.closeActiveInteractiveSurfaces()"
    )
    integrated_host_source =
      REPOSITORY_ROOT
        .join(
          "Sources/PocketRootIshRuntimeIntegration/" \
          "PocketRootIshWorkspaceHost.swift"
        )
        .binread
    integrated_workspace_source =
      REPOSITORY_ROOT
        .join(
          "Sources/PocketRootIshRuntimeIntegration/" \
          "PocketRootIshWorkspaceViewController.swift"
        )
        .binread
    assert_includes(
      integrated_host_source,
      "let controllers = workspaceControllerSnapshot()"
    )
    assert_includes(
      integrated_workspace_source,
      "closeSession { [self, host] in"
    )
    workspace_source =
      REPOSITORY_ROOT
        .join(
          "Sources/PocketRootTerminal/Public/" \
          "PocketRootWorkspaceViewController.swift"
        )
        .binread
    assert_includes workspace_source, "controller = current.parent"
    assert_includes workspace_source, "current.isMovingFromParent"
    assert_includes workspace_source, "current.isBeingDismissed"
    assert_includes source, "override func viewDidAppear(_ animated: Bool)"
    refute_includes source, "override func viewWillAppear(_ animated: Bool)"
    assert_match(
      /viewDidAppear.*?await workspaceHost\.refreshRuntimeState\(\)/m,
      source
    )

    info =
      REPOSITORY_ROOT
        .join("Examples/PocketRootHostApp/Sources/Info.plist")
        .binread
    assert_match(
      /<key>UIApplicationSupportsMultipleScenes<\/key>\s*<false\/>/,
      info
    )
  end

  def test_standalone_host_has_real_pty_and_files_ui_smoke
    project =
      REPOSITORY_ROOT
        .join("Examples/PocketRootHostApp/project.yml")
        .binread
    ui_test =
      REPOSITORY_ROOT
        .join(
          "Examples/PocketRootHostApp/UITests/PocketRootHostAppUITests.swift"
        )
        .binread
    host_source =
      REPOSITORY_ROOT
        .join("Examples/PocketRootHostApp/Sources/HostApp.swift")
        .binread
    runner =
      REPOSITORY_ROOT
        .join("Scripts/run-host-app-ui-smoke.sh")
        .binread
    generic_runner =
      REPOSITORY_ROOT
        .join("Scripts/run-ios-example-ui-smoke.sh")
        .binread
    device_runner =
      REPOSITORY_ROOT
        .join("Scripts/run-host-app-device-ui-smoke.sh")
        .binread
    workflow = REPOSITORY_ROOT.join(".github/workflows/ci.yml").binread

    assert_includes project, "PocketRootHostAppUITests:"
    assert_includes project, "type: bundle.ui-testing"
    assert_includes ui_test, "terminal.typeText("
    assert_includes ui_test, "PocketRootFiles.preview"
    assert_includes ui_test, '.matching(identifier: "ActivityListView")'
    refute_includes ui_test, 'app.otherElements["ActivityListView"]'
    assert_includes(
      ui_test,
      '"FullDocumentManagerViewControllerNavigationBar"'
    )
    assert_includes ui_test, "pickerLanding.waitForExistence(timeout: 30)"
    assert_includes ui_test, "hostDestination.waitForExistence(timeout: 30)"
    assert_includes ui_test, '"PocketRoot Host, Actions Menu"'
    refute_includes ui_test, "currentHostDocuments.waitForExistence(timeout: 3)"
    refute_includes(
      ui_test,
      'NSPredicate(format: "label BEGINSWITH %@", "PocketRoot Host")'
    )
    assert_operator(
      ui_test.index("pickerLanding.waitForExistence(timeout: 30)"),
      :<,
      ui_test.index("localLocation.tap()")
    )
    assert_includes ui_test, "testPTYLifecycleAndShutdown"
    assert_includes ui_test, "PocketRoot Host UI checkpoint"
    assert_includes ui_test, "testWorkspaceKeepsPTYAliveAcrossFilesTab"
    assert_includes(
      ui_test,
      "testIntegratedWorkspaceBootsAndOwnsShutdownOrdering"
    )
    assert_includes host_source, "PocketRootIshWorkspaceHost("
    assert_includes host_source, "workspaceHost.makeViewController()"
    assert_includes ui_test, "PocketRootHost.shutdown"
    assert_includes runner, "run-ios-example-ui-smoke.sh"
    assert_includes runner, "files-workspace"
    assert_includes runner, "pty-lifecycle"
    assert_includes generic_runner, "-test-timeouts-enabled YES"
    assert_includes generic_runner, "POCKETROOT_UI_SKIP_TESTING"
    assert_includes generic_runner, "POCKETROOT_UI_FAILURE_ARTIFACTS_DIR"
    assert_includes generic_runner, "POCKETROOT_UI_INFRASTRUCTURE_RETRY_LIMIT"
    assert_includes generic_runner, "is_retryable_simulator_launch_failure"
    assert_includes generic_runner, "is unknown to FrontBoard"
    assert_includes generic_runner, '"$CREATED_DEVICE" == "true"'
    assert_includes generic_runner, "xcodebuild-test-attempt-1.log"
    assert_includes generic_runner, "-attempt-1.xcresult"
    assert_includes device_runner, "build-for-testing"
    assert_includes device_runner, "test-without-building"
    assert_includes device_runner, "result.deviceProperties.osVersionNumber"
    assert_includes workflow, "./Scripts/run-host-app-ui-smoke.sh"
    assert_includes workflow, "actions/upload-artifact@043fb46d"
  end

  def test_rejects_demo_rootfs_injection_script_drift
    root = input_fixture
    path = root.join("Scripts/inject-demo-rootfs.sh")
    path.binwrite(
      path.binread.sub(
        'BUILD_CONFIGURATION="${CONFIGURATION:-Debug}"',
        'BUILD_CONFIGURATION="${CONFIGURATION:-Release}"'
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "repository input digest drifted"
  end

  def test_rejects_package_resolved_revision_drift
    root = input_fixture
    mutate_json(root.join("Package.resolved")) do |document|
      document.fetch("pins").fetch(0).fetch("state")["revision"] = "0" * 40
    end

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "Package.resolved external pins drifted"
  end

  def test_rejects_package_resolved_swiftterm_revision_drift
    root = input_fixture
    mutate_json(root.join("Package.resolved")) do |document|
      pin = document.fetch("pins").find do |candidate|
        candidate.fetch("identity") == "swiftterm"
      end
      pin.fetch("state")["revision"] = "0" * 40
    end

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "Package.resolved external pins drifted"
  end

  def test_rejects_package_resolved_version_drift
    root = input_fixture
    mutate_json(root.join("Package.resolved")) do |document|
      pin = document.fetch("pins").find do |candidate|
        candidate.fetch("identity") == "ish-arm64-pkg"
      end
      pin.fetch("state")["version"] = "0.4.0-abi.9"
    end

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "Package.resolved external pins drifted"
  end

  def test_rejects_package_manifest_exact_version_drift
    root = input_fixture
    path = root.join("Package.swift")
    path.binwrite(
      path.binread.sub(
        'exact: "0.4.0-abi.9.1"',
        'exact: "0.4.0-abi.9"'
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "external dependency declarations"
  end

  def test_rejects_package_resolved_origin_hash_drift
    root = input_fixture
    mutate_json(root.join("Package.resolved")) do |document|
      document["originHash"] = "0" * 64
    end

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "repository input digest drifted"
  end

  def test_rejects_package_manifest_product_drift
    root = input_fixture
    path = root.join("Package.swift")
    path.binwrite(
      path.binread.sub(
        'name: "PocketRootAgentRuntimeTools"',
        'name: "PocketRootAgentRuntimeToolsDrifted"'
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "Package.swift product graph drifted"
  end

  def test_rejects_unrecognized_package_product_and_target
    root = input_fixture
    path = root.join("Package.swift")
    contents = path.binread
    contents = contents.sub(
      "    products: [\n",
      "    products: [\n" \
        "        .executable(\n" \
        "            name: \"HiddenTool\",\n" \
        "            targets: [\"HiddenTool\"]\n" \
        "        ),\n"
    )
    contents = contents.sub(
      "    targets: [\n",
      "    targets: [\n" \
        "        .executableTarget(\n" \
        "            name: \"HiddenTool\"\n" \
        "        ),\n"
    )
    path.binwrite(contents)

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "unsupported product declaration"
  end

  def test_rejects_unrecognized_package_target_without_product
    root = input_fixture
    path = root.join("Package.swift")
    path.binwrite(
      path.binread.sub(
        "    targets: [\n",
        "    targets: [\n" \
          "        .executableTarget(name: \"HiddenTool\"),\n"
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "unsupported target declaration"
  end

  def test_rejects_unrecognized_package_dependency_form
    root = input_fixture
    path = root.join("Package.swift")
    path.binwrite(
      path.binread.sub(
        "    dependencies: [\n",
        "    dependencies: [\n" \
          "        .package(\n" \
          "            url: \"https://example.invalid/evil.git\",\n" \
          "            from: \"1.0.0\"\n" \
          "        ),\n"
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "external dependency declarations"
  end

  def test_rejects_unprojected_package_manifest_drift
    root = input_fixture
    path = root.join("Package.swift")
    contents = path.binread
    original = '.linkedLibrary("z")'
    assert_includes contents, original
    path.binwrite(contents.sub(original, '.linkedLibrary("sqlite3")'))

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "repository input digest drifted"
  end

  def test_rejects_package_target_dependency_drift
    root = input_fixture
    path = root.join("Package.swift")
    original =
      "\"PocketRootResources\"\n            ]\n        ),\n        .testTarget"
    replacement =
      original.sub(
        '"PocketRootResources"',
        '"PocketRootIshRuntimeIntegration"'
      )
    contents = path.binread
    assert_includes contents, original
    path.binwrite(contents.sub(original, replacement))

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "Package.swift target graph drifted"
  end

  def test_rejects_unparsed_package_target_dependency
    root = input_fixture
    path = root.join("Package.swift")
    path.binwrite(
      path.binread.sub(
        "\"PocketRootResources\"\n            ]\n        ),\n        .testTarget",
        "\"PocketRootResources\",\n" \
          "                .target(name: \"PocketRootIshRuntimeIntegration\")\n" \
          "            ]\n        ),\n        .testTarget"
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "unsupported dependency"
  end

  def test_rejects_package_test_target_dependency_drift
    root = input_fixture
    path = root.join("Package.swift")
    original =
      "\"PocketRootCore\"\n            ]\n        ),\n        .testTarget(\n" \
      "            name: \"PocketRootTerminalTests\""
    replacement =
      original.sub(
        '"PocketRootCore"',
        "\"PocketRootCore\",\n                \"PocketRootAgent\""
      )
    contents = path.binread
    assert_includes contents, original
    path.binwrite(contents.sub(original, replacement))

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "Package.swift test target graph drifted"
  end

  def test_rejects_application_product_composition_drift
    root = input_fixture
    path = root.join("Examples/PocketRootDemo/project.yml")
    path.binwrite(
      path.binread.sub(
        "product: PocketRootIshRuntimeIntegration",
        "product: PocketRoot"
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "project.yml target composition drifted"
  end

  def test_rejects_application_resource_path_drift
    root = input_fixture
    path = root.join("Examples/PocketRootDemo/project.yml")
    path.binwrite(
      path.binread.sub(
        "path: Sources/PocketRootDemo/Resources",
        "path: Spikes/PocketRootIshRuntimeSmoke"
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "project.yml target composition drifted"
  end

  def test_rejects_application_target_deployment_floor_drift
    root = input_fixture
    path = root.join("Examples/PocketRootDemo/project.yml")
    contents = path.binread
    original =
      "PocketRootDemo:\n    type: application\n    platform: iOS\n" \
      "    deploymentTarget: \"18.0\""
    assert_includes contents, original
    path.binwrite(
      contents.sub(original, original.sub('"18.0"', '"17.0"'))
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "project.yml target composition drifted"
  end

  def test_rejects_effective_global_application_deployment_override
    root = input_fixture
    path = root.join("Examples/PocketRootDemo/project.yml")
    contents = path.binread
    original = "    IPHONEOS_DEPLOYMENT_TARGET: \"18.0\""
    assert_includes contents, original
    path.binwrite(contents.sub(original, '    IPHONEOS_DEPLOYMENT_TARGET: "17.0"'))

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "exact project settings"
  end

  def test_rejects_effective_application_target_setting_override
    root = input_fixture
    path = root.join("Examples/PocketRootDemo/project.yml")
    contents = path.binread
    original =
      "    settings:\n      base:\n" \
      "        PRODUCT_BUNDLE_IDENTIFIER: com.jacklv.PocketRootDemo\n"
    replacement =
      "    settings:\n      base:\n" \
      "        IPHONEOS_DEPLOYMENT_TARGET: \"17.0\"\n" \
      "        PRODUCT_BUNDLE_IDENTIFIER: com.jacklv.PocketRootDemo\n"
    assert_includes contents, original
    path.binwrite(contents.sub(original, replacement))

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "project.yml target composition drifted"
  end

  def test_rejects_unexpected_default_product_resource
    root = input_fixture
    root.join(
      "Examples/PocketRootDemo/Sources/PocketRootDemo/Resources/" \
        "unreviewed-fs.tar.gz"
    ).binwrite("payload")

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "default product resource tree drifted"
  end

  def test_rejects_top_level_license_gate_drift
    root = input_fixture
    root.join("LICENSE").binwrite("MIT License\n")

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "approved MIT license"
  end

  def test_rejects_source_license_decision_that_contradicts_mit_text
    root = input_fixture
    mutate_json(
      root.join("Compliance/Release/RELEASE-DECISIONS.json")
    ) do |document|
      document.fetch("sourceRelease")["topLevelLicenseSpdx"] = "Apache-2.0"
    end

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message,
      "source release decision must match the approved MIT license"
  end

  def test_source_license_decision_allows_fail_closed_pending_state
    decisions =
      JSON.parse(
        REPOSITORY_ROOT
          .join("Compliance/Release/RELEASE-DECISIONS.json")
          .binread
      )
    decisions.fetch("sourceRelease")["topLevelLicenseSpdx"] = nil

    assert PocketRootReleaseCompliance.validate_source_license_decision(
      decisions
    )
  end

  def test_rejects_source_notice_and_contributor_policy_drift
    [
      [
        "NOTICE.md",
        "does not cover or relicense third-party components",
        "silently relicenses third-party components"
      ],
      [
        "CONTRIBUTING.en.md",
        "provided under the same MIT License",
        "provided under an unspecified license"
      ]
    ].each_with_index do |(relative, expected, replacement), index|
      root = input_fixture("source-policy-#{index}")
      path = root.join(relative)
      path.binwrite(path.binread.sub(expected, replacement))

      error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
        PocketRootReleaseCompliance.build_outputs(root)
      end

      assert_includes error.message,
        "source release notice or contributor policy drifted"
    end
  end

  def test_rejects_rootfs_distribution_approval_drift
    root = input_fixture
    mutate_json(
      root.join("Compliance/RootFS/v0.3.3/EVIDENCE.json")
    ) do |document|
      document.fetch("engineeringStatus")["redistributionApproved"] = true
    end

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "RootFS compliance evidence digest drifted"
  end

  def test_rejects_rootfs_package_coverage_drift
    root = input_fixture
    mutate_json(
      root.join("Compliance/RootFS/v0.3.3/SBOM.spdx.json")
    ) do |document|
      document.fetch("packages").pop
    end

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "RootFS compliance evidence digest drifted"
  end

  def test_rejects_rootfs_package_metadata_drift
    root = input_fixture
    mutate_json(
      root.join("Compliance/RootFS/v0.3.3/SBOM.spdx.json")
    ) do |document|
      document.fetch("packages").fetch(0)["name"] = "tampered"
    end

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "RootFS compliance evidence digest drifted"
  end

  def test_rejects_runtime_rootfs_manifest_and_identity_gate_drift
    mutations = {
      "Sources/PocketRootResources/RootFSArtifactManifest.swift" => [
        'version: "v0.3.3"',
        'version: "v9.9.9"'
      ],
      "Sources/PocketRootIshRuntime/Public/" \
        "PocketRootIshRuntimeConfiguration.swift" => [
        'expectedOperatingSystemVersionID: "3.19.1"',
        'expectedOperatingSystemVersionID: "9.9.9"'
      ],
      "Sources/PocketRootIshRuntimeIntegration/" \
        "PocketRootIshSystemFactory.swift" => [
        "manifest == .ishEmbedV0_3_3 ? .ishEmbedV0_3_3 : .alpineARM64",
        "manifest == .ishEmbedV0_3_3 ? .alpineARM64 : .alpineARM64"
      ],
      "Sources/PocketRootIshRuntime/Runtime/IshRuntimeHealthCheck.swift" => [
        'configuration.expectedOperatingSystemID',
        '"tampered-operating-system-id"'
      ],
      "Sources/PocketRootResources/RootFSValidator.swift" => [
        "against manifest: PocketRootRootFSArtifactManifest = .ishEmbedV0_3_3",
        "against manifest: PocketRootRootFSArtifactManifest = .init("
      ],
      "Sources/PocketRootResources/RootFSInstaller.swift" => [
        "manifest: PocketRootRootFSArtifactManifest = .ishEmbedV0_3_3",
        "manifest: PocketRootRootFSArtifactManifest = .init("
      ]
    }

    mutations.each_with_index do |(relative, replacement), index|
      root = input_fixture("runtime-rootfs-#{index}")
      path = root.join(relative)
      contents = path.binread
      assert_includes contents, replacement.fetch(0)
      path.binwrite(contents.sub(*replacement))

      error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
        PocketRootReleaseCompliance.check(
          PocketRootReleaseCompliance.output_directory,
          root
        )
      end

      assert_includes error.message, "release compliance output is stale"
    end
  end

  def test_rejects_dangling_release_sbom_relationship
    outputs = PocketRootReleaseCompliance.build_outputs
    composition = JSON.parse(outputs.fetch("COMPOSITION.json"))
    sbom = JSON.parse(outputs.fetch("SBOM.spdx.json"))
    sbom.fetch("relationships").fetch(0)["relatedSpdxElement"] =
      "SPDXRef-Package-Missing"

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.validate_sbom(sbom, composition)
    end

    assert_includes error.message, "dangling ID"
  end

  def test_rejects_non_schema_spdx_package_purpose
    outputs = PocketRootReleaseCompliance.build_outputs
    composition = JSON.parse(outputs.fetch("COMPOSITION.json"))
    sbom = JSON.parse(outputs.fetch("SBOM.spdx.json"))
    rootfs_package = sbom.fetch("packages").find do |package|
      package.fetch("SPDXID") == "SPDXRef-Package-External-RootFS"
    end
    rootfs_package["primaryPackagePurpose"] = "OPERATING-SYSTEM"

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.validate_sbom(sbom, composition)
    end

    assert_includes error.message, "package analysis state drifted"
  end

  def test_rejects_release_authorization_gate_drift
    outputs = PocketRootReleaseCompliance.build_outputs
    composition = JSON.parse(outputs.fetch("COMPOSITION.json"))
    composition.fetch("coverage")["distributionAuthorized"] = true

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.validate_composition(composition)
    end

    assert_includes error.message, "exact coverage gates"
  end

  def test_materializes_new_external_directory_and_rejects_existing_output
    output = @temporary_directory.join("candidate")
    resolved_output = output.parent.realpath.join(output.basename)

    assert_equal resolved_output, PocketRootReleaseCompliance.materialize(output)
    assert_equal(
      PocketRootReleaseCompliance::OUTPUT_FILENAMES.sort,
      output.children.map { |path| path.basename.to_s }.sort
    )
    assert PocketRootReleaseCompliance.check(output)

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.materialize(output)
    end
    assert_includes error.message, "already exists"
  end

  def test_materialization_uses_one_resolved_parent
    real_parent = @temporary_directory.join("real-parent")
    real_parent.mkpath
    nested_parent = real_parent.join("nested")
    nested_parent.mkdir
    alias_parent = @temporary_directory.join("parent-alias")
    File.symlink(real_parent, alias_parent)
    requested_output = alias_parent.join("nested/candidate")
    resolved_output = nested_parent.realpath.join("candidate")

    assert_equal(
      resolved_output,
      PocketRootReleaseCompliance.materialize(requested_output)
    )
    assert resolved_output.directory?
    assert PocketRootReleaseCompliance.check(resolved_output)
  end

  def test_rejects_relative_and_in_repository_output_paths
    relative_error =
      assert_raises(PocketRootReleaseCompliance::ComplianceError) do
        PocketRootReleaseCompliance.materialize(Pathname("candidate"))
      end
    assert_includes relative_error.message, "must be absolute"

    repository_output =
      REPOSITORY_ROOT.join("Compliance/Release/test-materialization")
    repository_error =
      assert_raises(PocketRootReleaseCompliance::ComplianceError) do
        PocketRootReleaseCompliance.materialize(repository_output)
      end
    assert_includes repository_error.message, "outside the repository"
    refute repository_output.exist?
  end

  def test_check_rejects_an_unexpected_file
    output = @temporary_directory.join("candidate")
    PocketRootReleaseCompliance.materialize(output)
    output.join("unexpected.txt").binwrite("unexpected")

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.check(output)
    end

    assert_includes error.message, "file set drifted"
  end

  private

  def runtime_ready_coverage
    %w[
      releaseArtifactBuilt
      releaseArtifactScanned
      binaryFilesAnalyzed
      completeReleaseArtifactSBOM
      topLevelLicenseFinalized
      completeLicenseAndNoticeBundle
      correspondingSourceDeliveryApproved
      appStorePolicyApproved
      legalReviewApproved
      distributionAuthorized
    ]
  end

  def reviewed_runtime_authorization_decisions(
    artifact_sha256: "a" * 64
  )
    decisions =
      JSON.parse(
        REPOSITORY_ROOT
          .join("Compliance/Release/RELEASE-DECISIONS.json")
          .binread
      )
    decisions["status"] = "source-and-runtime-distribution-authorized"
    decisions.fetch("sourceRelease")["topLevelLicenseSpdx"] = "MIT"
    runtime = decisions.fetch("runtimeDistribution")
    runtime["finalArtifactSha256"] = artifact_sha256
    %w[
      completeLicenseAndNoticeBundleApproved
      correspondingSourceDeliveryApproved
      appStorePolicyApproved
      privacyReviewApproved
      legalReviewApproved
      distributionAuthorized
    ].each do |key|
      runtime[key] = true
    end
    approval = decisions.fetch("approval")
    approval["approvedBy"] = "project-owner"
    approval["approvedAt"] = "2026-07-31T12:00:00Z"
    approval["notes"] = "Reviewed RootFS-excluding runtime authorization."
    decisions
  end

  def write_final_artifact_evidence(
    root,
    include_rootfs: false,
    release_signed: true,
    binary_get_task_allow: nil,
    omit_nested_mach_o: false
  )
    files = [
      {
        "path" => "PocketRootDemo",
        "byteCount" => 16,
        "mode" => "0755",
        "sha1" => "1" * 40,
        "sha256" => "1" * 64,
        "machO" => true
      }
    ]
    if include_rootfs
      files << {
        "path" => "Resources/fs.tar.gz",
        "byteCount" => PocketRootReleaseCompliance::ROOTFS.fetch("byteCount"),
        "mode" => "0644",
        "sha1" => "2" * 40,
        "sha256" => PocketRootReleaseCompliance::ROOTFS.fetch("sha256"),
        "machO" => false
      }
    end
    if omit_nested_mach_o
      files << {
        "path" => "Frameworks/Omitted",
        "byteCount" => 8,
        "mode" => "0755",
        "sha1" => "3" * 40,
        "sha256" => "3" * 64,
        "machO" => true
      }
    end
    files.sort_by! { |file| file.fetch("path") }
    directories = []
    directories << {"path" => "Resources", "mode" => "0755"} if include_rootfs
    if omit_nested_mach_o
      directories << {"path" => "Frameworks", "mode" => "0755"}
    end
    directories.sort_by! { |directory| directory.fetch("path") }
    artifact_sha256 =
      PocketRootReleaseArtifactScanner.artifact_digest(files, directories)
    inventory = {
      "schemaVersion" => PocketRootReleaseArtifactScanner::SCHEMA_VERSION,
      "generatedAt" => PocketRootReleaseArtifactScanner::GENERATED_AT,
      "status" => "engineering-artifact-scan-not-distribution-candidate",
      "input" => {
        "kind" => "xcarchive",
        "applicationRelativePath" =>
          "Products/Applications/PocketRootDemo.app"
      },
      "application" => {
        "bundleIdentifier" => "com.jacklv.PocketRootDemo",
        "displayName" => "PocketRoot",
        "executable" => "PocketRootDemo",
        "shortVersion" => "0.1.0",
        "buildVersion" => "1",
        "minimumOSVersion" => "18.0",
        "platformName" => "iphoneos",
        "sdkName" => "iphoneos",
        "deviceFamilies" => [1, 2]
      },
      "artifact" => {
        "sha256" => artifact_sha256,
        "directoryCount" => directories.length,
        "fileCount" => files.length,
        "machOFileCount" => 1,
        "totalByteCount" =>
          files.sum { |file| file.fetch("byteCount") }
      },
      "limits" => {},
      "signature" => {
        "status" => release_signed ? "signed-valid" : "unsigned",
        "valid" => release_signed,
        "entitlements" =>
          release_signed ?
            {
              "application-identifier" =>
                "ABCDE12345.com.jacklv.PocketRootDemo",
              "com.apple.developer.team-identifier" => "ABCDE12345",
              "get-task-allow" => false
            } : {}
      },
      "riskSignals" => {
        "invalidSignature" => false,
        "invalidCodeObjects" => [],
        "jitEntitlements" => [],
        "mapJITBinaries" => [],
        "privateEntitlements" => [],
        "privateFrameworkDependencies" => []
      },
      "directories" => directories,
      "files" => files,
      "machOBinaries" => [
        {
          "path" => "PocketRootDemo",
          "sha256" => "1" * 64,
          "architectures" => ["arm64"],
          "dependencies" => [],
          "undefinedSymbols" => [],
          "signature" => {
            "status" => release_signed ? "signed-valid" : "unsigned",
            "valid" => release_signed,
            "entitlements" =>
              binary_get_task_allow.nil? ?
                {} : {"get-task-allow" => binary_get_task_allow}
          },
          "signals" => {
            "mapJITString" => false,
            "privateFrameworkDependencies" => []
          }
        }
      ],
      "coverage" => PocketRootReleaseArtifactScanner::RELEASE_GATES.dup
    }
    sbom = PocketRootReleaseArtifactScanner.build_sbom(inventory)
    evidence_directory =
      root.join(
        PocketRootReleaseCompliance::FINAL_ARTIFACT_EVIDENCE_RELATIVE
      )
    evidence_directory.mkpath
    evidence_directory.join("ARTIFACT-INVENTORY.json").binwrite(
      PocketRootReleaseArtifactScanner.pretty_json(inventory)
    )
    evidence_directory.join("SBOM.spdx.json").binwrite(
      PocketRootReleaseArtifactScanner.pretty_json(sbom)
    )
  end

  def spdx_license_list
    @spdx_license_list ||=
      JSON.parse(
        REPOSITORY_ROOT
          .join("Compliance/SPDX/LICENSE-LIST-3.28.0.json")
          .binread
      )
  end

  def input_fixture(name = "repository")
    root = @temporary_directory.join(name)
    root.mkpath
    INPUT_PATHS.each do |relative|
      source = REPOSITORY_ROOT.join(relative)
      destination = root.join(relative)
      destination.dirname.mkpath
      FileUtils.copy_file(source, destination)
    end
    PocketRootReleaseCompliance::IMPLEMENTATION_ROOTS.each do |relative|
      source = REPOSITORY_ROOT.join(relative)
      destination = root.join(relative)
      destination.dirname.mkpath
      FileUtils.cp_r(source, destination)
    end
    root
  end

  def mutate_json(path)
    document = JSON.parse(path.binread)
    yield document
    path.binwrite(PocketRootReleaseCompliance.pretty_json(document))
  end
end
