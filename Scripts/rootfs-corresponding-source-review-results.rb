#!/usr/bin/env ruby

require "digest"
require "json"
require "pathname"
require_relative "rootfs-source-acquisition"

module RootFSCorrespondingSourceReviewResults
  DEFAULT_DIRECTORY = Pathname("Compliance/RootFS/v0.3.3")
  ARCHIVE_VERSION = "v0.3.3"
  ARCHIVE_SHA256 =
    "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
  STATUS =
    "candidate-corresponding-source-material-engineering-reviewed-open-release-gates"
  REVIEW_STATE =
    "candidate-source-material-engineering-reviewed-delivery-approval-open"
  ENGINEERING_CONCLUSION =
    "candidate-source-material-complete-engineering-only"
  SOURCE_STATUS =
    "candidate-material-engineering-reviewed-external-bundle-required"
  RESOLVED_REVIEW_ITEMS = %w[
    bind-source-material-to-installed-binaries
    pin-complete-aports-recipe-tree
    pin-declared-upstream-distfiles
  ].freeze
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/
  TOP_LEVEL_KEYS = %w[
    allSourceOriginsReviewed archive candidateBundleMaterializerReady
    completeCandidateSourceMaterialIndexPresent
    completeCorrespondingSourceBundlePresent
    correspondingSourceDeliveryApproved engineeringReviewCompleted
    legalReviewApproved rebuildEnvironmentVerified redistributionApproved
    reviewedCanonicalAportsEntryCount reviewedDistfileCount
    reviewedSourceOriginCount schemaVersion sourceAcquisitionSha256
    sourceOriginsWithRemainingMaterialItems sources status
  ].freeze
  SOURCE_INVENTORY_KEYS = %w[
    archive candidateBundleMaterializerReady
    completeCorrespondingSourceBundlePresent
    correspondingSourceCandidateEngineeringReviewCompleted
    correspondingSourceDeliveryApproved rebuildEnvironmentVerified
    schemaVersion sourceOrigins status
  ].freeze
  SOURCE_KEYS = %w[
    aportsCommit binaryPackages containsDeclaredCopyleft
    declaredLicenseExpressions engineeringConclusion materialCoverage
    remainingReviewItems resolvedReviewItems reviewState
    reviewedCanonicalAportsEntryCount reviewedDistfileCount sourceOrigin
  ].freeze

  class ValidationError < StandardError
  end

  module_function

  def load_json_document(path, label)
    pathname = Pathname(path)
    unless pathname.exist? && !pathname.symlink? && pathname.lstat.file?
      raise ValidationError,
        "#{label} is not a real regular file: #{path}"
    end

    contents = pathname.binread
    {
      document: JSON.parse(contents),
      contents: contents
    }
  rescue JSON::ParserError => error
    raise ValidationError, "#{label} is invalid JSON: #{error.message}"
  end

  def load_json(path, label)
    load_json_document(path, label).fetch(:document)
  end

  def resolve_paths(arguments)
    unless arguments.length <= 3
      raise ValidationError, "expected at most three manifest paths"
    end
    directory =
      Pathname(
        arguments.fetch(
          0,
          DEFAULT_DIRECTORY
            .join("CORRESPONDING-SOURCE-REVIEW-RESULTS.json")
            .to_s
        )
      ).dirname

    [
      arguments.fetch(
        0,
        directory.join("CORRESPONDING-SOURCE-REVIEW-RESULTS.json").to_s
      ),
      arguments.fetch(
        1,
        directory.join("SOURCE-ACQUISITION.json").to_s
      ),
      arguments.fetch(
        2,
        directory.join("SOURCE-INVENTORY.json").to_s
      )
    ]
  end

  def validate_manifest(
    manifest,
    source_acquisition,
    source_inventory,
    source_acquisition_bytes:,
    allow_file_urls: false
  )
    require_hash(manifest, "corresponding-source review results")
    require_hash(source_acquisition, "source acquisition manifest")
    require_hash(source_inventory, "source inventory")
    unless source_inventory.keys.sort == SOURCE_INVENTORY_KEYS.sort &&
      source_inventory["schemaVersion"] == 1 &&
      source_inventory["completeCorrespondingSourceBundlePresent"] == false &&
      source_inventory[
        "correspondingSourceCandidateEngineeringReviewCompleted"
      ] == true &&
      source_inventory["candidateBundleMaterializerReady"] == true &&
      source_inventory["rebuildEnvironmentVerified"] == false &&
      source_inventory["correspondingSourceDeliveryApproved"] == false &&
      source_inventory["status"] == SOURCE_STATUS
      raise ValidationError,
        "source inventory does not preserve corresponding-source release gates"
    end
    unless manifest.keys.sort == TOP_LEVEL_KEYS.sort
      raise ValidationError,
        "corresponding-source review results have unexpected fields"
    end
    unless manifest["schemaVersion"] == 1 &&
      manifest["archive"] == {
        "version" => ARCHIVE_VERSION,
        "sha256" => ARCHIVE_SHA256
      }
      raise ValidationError,
        "corresponding-source review results do not match the pinned archive"
    end
    expected_acquisition_sha256 =
      Digest::SHA256.hexdigest(source_acquisition_bytes)
    unless manifest["sourceAcquisitionSha256"] ==
      expected_acquisition_sha256 &&
      expected_acquisition_sha256.match?(SHA256_PATTERN)
      raise ValidationError,
        "corresponding-source review results do not match source acquisition bytes"
    end

    begin
      acquisition_sources = RootFSSourceAcquisition.validate_manifest(
        source_acquisition,
        source_inventory,
        allow_file_urls: allow_file_urls
      )
    rescue RootFSSourceAcquisition::ValidationError => error
      raise ValidationError,
        "corresponding-source review inputs are invalid: #{error.message}"
    end

    unless manifest["status"] == STATUS &&
      manifest["engineeringReviewCompleted"] == true &&
      manifest["allSourceOriginsReviewed"] == true &&
      manifest["completeCandidateSourceMaterialIndexPresent"] == true &&
      manifest["candidateBundleMaterializerReady"] == true &&
      manifest["completeCorrespondingSourceBundlePresent"] == false &&
      manifest["rebuildEnvironmentVerified"] == false &&
      manifest["correspondingSourceDeliveryApproved"] == false &&
      manifest["legalReviewApproved"] == false &&
      manifest["redistributionApproved"] == false
      raise ValidationError,
        "corresponding-source review results do not preserve open release gates"
    end

    inventory_sources = source_inventory.fetch("sourceOrigins").to_h do |entry|
      [entry.fetch("sourceOrigin"), entry]
    end
    result_sources = manifest["sources"]
    unless result_sources.is_a?(Array) &&
      result_sources.length == acquisition_sources.length
      raise ValidationError,
        "corresponding-source review results must cover every source origin"
    end

    seen = {}
    canonical_entry_total = 0
    distfile_total = 0
    result_sources.each_with_index do |result, index|
      require_hash(result, "sources[#{index}]")
      unless result.keys.sort == SOURCE_KEYS.sort
        raise ValidationError,
          "corresponding-source source result has unexpected fields"
      end
      origin = result["sourceOrigin"]
      unless origin.is_a?(String) && !origin.empty? && !seen[origin]
        raise ValidationError,
          "corresponding-source source results contain an invalid or duplicate origin"
      end
      seen[origin] = true

      acquisition = acquisition_sources.find do |entry|
        entry.fetch("sourceOrigin") == origin
      end
      inventory = inventory_sources[origin]
      unless acquisition && inventory
        raise ValidationError,
          "corresponding-source source result is not in the pinned inventory: #{origin}"
      end
      expected_entry_count =
        acquisition.fetch("aportsSnapshot").fetch("regularFileCount")
      expected_distfile_count = acquisition.fetch("distfiles").length
      inventory_copyleft = inventory["containsDeclaredCopyleft"]
      result_copyleft = result["containsDeclaredCopyleft"]
      unless result["aportsCommit"] == acquisition["aportsCommit"] &&
        result["binaryPackages"] == inventory["binaryPackages"] &&
        result["declaredLicenseExpressions"] ==
          inventory["declaredLicenseExpressions"] &&
        [true, false].include?(inventory_copyleft) &&
        [true, false].include?(result_copyleft) &&
        result_copyleft == inventory_copyleft &&
        inventory["correspondingSourceStatus"] == SOURCE_STATUS &&
        result["reviewedCanonicalAportsEntryCount"] ==
          expected_entry_count &&
        result["reviewedDistfileCount"] == expected_distfile_count &&
        result["materialCoverage"] == "complete" &&
        result["reviewState"] == REVIEW_STATE &&
        result["resolvedReviewItems"] == RESOLVED_REVIEW_ITEMS &&
        result["remainingReviewItems"] == [] &&
        result["engineeringConclusion"] == ENGINEERING_CONCLUSION
        raise ValidationError,
          "corresponding-source source result does not match #{origin}"
      end
      canonical_entry_total += expected_entry_count
      distfile_total += expected_distfile_count
    end

    unless seen.keys.sort == inventory_sources.keys.sort &&
      manifest["reviewedSourceOriginCount"] == acquisition_sources.length &&
      manifest["reviewedCanonicalAportsEntryCount"] ==
        canonical_entry_total &&
      manifest["reviewedDistfileCount"] == distfile_total &&
      manifest["sourceOriginsWithRemainingMaterialItems"] == 0
      raise ValidationError,
        "corresponding-source review result totals do not match pinned inputs"
    end

    result_sources
  rescue KeyError => error
    raise ValidationError,
      "corresponding-source review results are incomplete: #{error.message}"
  end

  def require_hash(value, label)
    raise ValidationError, "#{label} must be an object" unless value.is_a?(Hash)

    value
  end
  private_class_method :require_hash
end

if $PROGRAM_NAME == __FILE__
  begin
    results_path, acquisition_path, inventory_path =
      RootFSCorrespondingSourceReviewResults.resolve_paths(ARGV)
    results =
      RootFSCorrespondingSourceReviewResults.load_json(
        results_path,
        "corresponding-source review results"
      )
    acquisition_input =
      RootFSCorrespondingSourceReviewResults.load_json_document(
        acquisition_path,
        "source acquisition manifest"
      )
    acquisition_bytes = acquisition_input.fetch(:contents)
    acquisition = acquisition_input.fetch(:document)
    inventory =
      RootFSCorrespondingSourceReviewResults.load_json(
        inventory_path,
        "source inventory"
      )
    sources =
      RootFSCorrespondingSourceReviewResults.validate_manifest(
        results,
        acquisition,
        inventory,
        source_acquisition_bytes: acquisition_bytes
      )
    puts "RootFS corresponding-source candidate review results are valid " \
      "(#{sources.length} source origins)."
  rescue RootFSCorrespondingSourceReviewResults::ValidationError,
    JSON::ParserError, SystemCallError => error
    warn error.message
    exit 1
  end
end
