#!/usr/bin/env ruby

require "json"
require "minitest/autorun"
require "pathname"
require_relative "../../Scripts/rootfs-rebuild-delivery-evidence"

class RootFSRebuildDeliveryEvidenceTests < Minitest::Test
  REPOSITORY_ROOT = Pathname(__dir__).join("../..").expand_path
  DIRECTORY = REPOSITORY_ROOT.join("Compliance/RootFS/v0.3.3")

  def load_document(filename)
    path = DIRECTORY.join(filename)
    [JSON.parse(path.binread), path.binread]
  end

  def build_outputs(
    source_acquisition: nil,
    source_inventory: nil,
    review: nil
  )
    actual_source_acquisition, source_acquisition_bytes =
      load_document("SOURCE-ACQUISITION.json")
    actual_source_inventory, source_inventory_bytes =
      load_document("SOURCE-INVENTORY.json")
    actual_review, review_bytes =
      load_document("CORRESPONDING-SOURCE-REVIEW-RESULTS.json")
    selected_source_acquisition =
      source_acquisition || actual_source_acquisition
    selected_source_inventory = source_inventory || actual_source_inventory
    selected_review = review || actual_review

    RootFSRebuildDeliveryEvidence.build(
      source_acquisition: selected_source_acquisition,
      source_inventory: selected_source_inventory,
      corresponding_source_review_results: selected_review,
      source_acquisition_bytes:
        source_acquisition ? JSON.generate(selected_source_acquisition) :
          source_acquisition_bytes,
      source_inventory_bytes:
        source_inventory ? JSON.generate(selected_source_inventory) :
          source_inventory_bytes,
      corresponding_source_review_results_bytes:
        review ? JSON.generate(selected_review) : review_bytes
    )
  end

  def test_checked_in_evidence_is_reproducible
    outputs = RootFSRebuildDeliveryEvidence.check(DIRECTORY)

    assert_equal(
      %w[
        REBUILD-ENVIRONMENT-REVIEW.json
        SOURCE-DELIVERY-INVENTORY.json
      ],
      outputs.keys.sort
    )
  end

  def test_published_archive_and_successor_claims_stay_distinct
    outputs = build_outputs
    review = JSON.parse(outputs.fetch("REBUILD-ENVIRONMENT-REVIEW.json"))
    published = review.fetch("publishedArchiveBuild")
    successor = review.fetch("successorCandidateBuild")
    conclusions = review.fetch("conclusions")

    assert_equal true, published.fetch("sourceIdentified")
    assert_equal "v0.3.3",
      published.fetch("builderSource").fetch("releaseTag")
    assert_equal "scripts/build-rootfs.sh",
      published.fetch("builderSource").fetch("buildScriptPath")
    assert_equal false, published.fetch("exactBuildEnvironmentCaptured")
    assert_equal false, published.fetch("exactPublishedArchiveRebuildVerified")
    assert_equal "scripts/build-rootfs.sh",
      successor.fetch("builderSource").fetch("buildScriptPath")
    assert_equal "scripts/prepare-rootfs-candidate.sh",
      successor.fetch("builderSource").fetch("candidateScriptPath")
    assert_equal "scripts/capture-rootfs-build-environment.py",
      successor.fetch("builderSource").fetch("captureScriptPath")
    assert_equal "scripts/alpine-rootfs-pin.sh",
      successor.fetch("builderSource").fetch("rootfsPinPath")
    assert_equal 2, successor.fetch("independentInvocationCount")
    assert_equal 4, successor.fetch("totalComparedBuildCount")
    assert_equal true, successor.fetch("crossInvocationByteEqualityVerified")
    assert_equal false, successor.fetch("hostToolBytesEqualAcrossInvocations")
    assert_equal true,
      successor.fetch("hostToolSourceProvenanceEqualAcrossInvocations")
    assert_equal false, successor.fetch("crossHostReproducibilityVerified")
    assert_equal false, successor.fetch("distributionAuthorized")
    assert_equal false,
      conclusions.fetch("successorCandidateMayReplacePinnedArchive")

    invocations = successor.fetch("invocations")
    refute_equal(
      invocations.fetch(0).fetch("hostFakefsifySHA256"),
      invocations.fetch(1).fetch("hostFakefsifySHA256")
    )
  end

  def test_delivery_inventory_keeps_materialization_and_approval_gates_closed
    outputs = build_outputs
    inventory = JSON.parse(outputs.fetch("SOURCE-DELIVERY-INVENTORY.json"))
    coverage = inventory.fetch("coverage")

    assert_equal 5, coverage.fetch("deliveryUnitCount")
    assert_equal true, coverage.fetch("candidateSourceMaterialIndexComplete")
    assert_equal true, coverage.fetch("modificationDisclosureIndexed")
    assert_equal "Scripts/prepare-rootfs-delivery-candidate.rb",
      coverage.fetch("deliveryCandidateMaterializer")
    assert_equal true, coverage.fetch("deliveryCandidateMaterializerReady")
    assert_equal false,
      coverage.fetch("materializedCorrespondingSourceBundlePresent")
    assert_equal false, coverage.fetch("completeLicenseAndNoticeBundlePresent")
    assert_equal false, coverage.fetch("sourceOfferPrepared")
    assert_equal false, coverage.fetch("deliveryMechanismApproved")
    assert_equal false, coverage.fetch("legalReviewApproved")
    assert_equal false, coverage.fetch("redistributionApproved")
  end

  def test_tampered_archive_binding_is_rejected
    source_acquisition, = load_document("SOURCE-ACQUISITION.json")
    source_acquisition["archive"]["sha256"] = "0" * 64

    error = assert_raises(RootFSRebuildDeliveryEvidence::ValidationError) do
      build_outputs(source_acquisition: source_acquisition)
    end
    assert_includes error.message, "does not bind the pinned RootFS archive"
  end

  def test_open_release_gate_drift_is_rejected
    review, = load_document("CORRESPONDING-SOURCE-REVIEW-RESULTS.json")
    review["redistributionApproved"] = true

    error = assert_raises(RootFSRebuildDeliveryEvidence::ValidationError) do
      build_outputs(review: review)
    end
    assert_includes error.message, "release gates"
  end
end
