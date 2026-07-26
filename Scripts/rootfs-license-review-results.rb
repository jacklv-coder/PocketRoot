#!/usr/bin/env ruby

require "digest"
require "json"
require "pathname"
require_relative "rootfs-license-review"
require_relative "rootfs-source-acquisition"

module RootFSLicenseReviewResults
  DEFAULT_MANIFEST_DIRECTORY = Pathname("Compliance/RootFS/v0.3.3")
  ARCHIVE_VERSION = "v0.3.3"
  ARCHIVE_SHA256 =
    "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
  STATUS = "engineering-reviewed-open-release-gates"
  REVIEW_STATE = "engineering-reviewed-legal-review-open"
  COVERAGE = %w[complete partial declaration-only not-applicable-no-payload].freeze
  CONCLUSIONS = %w[
    attribution-list
    complete-license-and-attribution-notice
    complete-license-text
    inline-license-and-attribution-notice
    license-declaration
    license-header-and-attribution
    license-reference-and-attribution
  ].freeze

  class ValidationError < StandardError
  end

  module_function

  def load_json(path, label)
    pathname = Pathname(path)
    raise ValidationError, "#{label} is not a regular file: #{path}" unless pathname.file?

    JSON.parse(pathname.binread)
  rescue JSON::ParserError => error
    raise ValidationError, "#{label} is invalid JSON: #{error.message}"
  end

  def require_hash(value, label)
    raise ValidationError, "#{label} must be an object" unless value.is_a?(Hash)

    value
  end

  def require_string_array(value, label, allow_empty: false)
    unless value.is_a?(Array) &&
      (allow_empty || !value.empty?) &&
      value.all? { |entry| entry.is_a?(String) && !entry.empty? } &&
      value.uniq.length == value.length
      raise ValidationError, "#{label} must be a unique string array"
    end

    value
  end

  def require_bytes_backed_document(document, bytes, label)
    parsed = JSON.parse(bytes)
    unless document.eql?(parsed)
      raise ValidationError, "#{label} object does not match supplied bytes"
    end

    parsed
  rescue JSON::ParserError => error
    raise ValidationError, "#{label} bytes are invalid JSON: #{error.message}"
  end

  def resolve_manifest_paths(arguments)
    unless arguments.length <= 4
      raise ValidationError,
        "usage: rootfs-license-review-results.rb " \
        "[RESULTS REVIEW [SOURCE_ACQUISITION [SOURCE_INVENTORY]]]"
    end

    results_path =
      arguments.fetch(
        0,
        DEFAULT_MANIFEST_DIRECTORY.join("LICENSE-REVIEW-RESULTS.json").to_s
      )
    review_path =
      arguments.fetch(
        1,
        DEFAULT_MANIFEST_DIRECTORY.join("LICENSE-REVIEW.json").to_s
      )
    source_acquisition_path =
      arguments.fetch(
        2,
        Pathname(review_path).dirname.join("SOURCE-ACQUISITION.json").to_s
      )
    source_inventory_path =
      arguments.fetch(
        3,
        Pathname(source_acquisition_path)
          .dirname
          .join("SOURCE-INVENTORY.json")
          .to_s
      )

    [
      results_path,
      review_path,
      source_acquisition_path,
      source_inventory_path
    ]
  end

  def validate_candidate_results(results, candidates, origin)
    unless results.is_a?(Array) && results.length == candidates.length
      raise ValidationError,
        "candidate results for #{origin} must cover every indexed candidate"
    end

    results.each_with_index do |result, offset|
      require_hash(result, "candidate result for #{origin}")
      candidate = candidates.fetch(offset)
      unless result.keys.sort == %w[conclusion outputPath sha256].sort &&
        result["outputPath"] == candidate["outputPath"] &&
        result["sha256"] == candidate["sha256"] &&
        CONCLUSIONS.include?(result["conclusion"])
        raise ValidationError,
          "candidate result for #{origin} does not match the indexed evidence"
      end
    end
  end

  def validate_manifest(
    manifest,
    license_review,
    source_acquisition:,
    source_inventory:,
    license_review_bytes:,
    source_acquisition_bytes:,
    allow_file_urls: false
  )
    require_hash(manifest, "license review results")
    require_hash(license_review, "license review manifest")
    require_bytes_backed_document(
      license_review,
      license_review_bytes,
      "license review manifest"
    )
    require_bytes_backed_document(
      source_acquisition,
      source_acquisition_bytes,
      "source acquisition manifest"
    )
    unless manifest["schemaVersion"] == 1 &&
      manifest["archive"] == {
        "version" => ARCHIVE_VERSION,
        "sha256" => ARCHIVE_SHA256
      }
      raise ValidationError,
        "license review results do not match the pinned archive"
    end
    unless manifest["licenseReviewManifestSha256"] ==
      Digest::SHA256.hexdigest(license_review_bytes)
      raise ValidationError,
        "license review results do not match LICENSE-REVIEW.json bytes"
    end
    begin
      RootFSSourceAcquisition.validate_manifest(
        source_acquisition,
        source_inventory,
        allow_file_urls: allow_file_urls
      )
      RootFSLicenseReview.validate_manifest(
        license_review,
        source_acquisition,
        source_inventory,
        source_acquisition_bytes: source_acquisition_bytes
      )
    rescue RootFSSourceAcquisition::ValidationError,
      RootFSLicenseReview::ValidationError => error
      raise ValidationError,
        "license review results reference an invalid manifest: #{error.message}"
    end
    unless manifest["status"] == STATUS &&
      manifest["engineeringReviewCompleted"] == true &&
      manifest["allCandidateDigestsVerified"] == true &&
      manifest["completeLicenseTextBundlePresent"] == false &&
      manifest["completePackageNoticeSetPresent"] == false &&
      manifest["legalReviewApproved"] == false &&
      manifest["redistributionApproved"] == false
      raise ValidationError,
        "license review results do not preserve the open release gates"
    end

    review_sources = license_review["sources"]
    result_sources = manifest["sources"]
    unless review_sources.is_a?(Array) &&
      result_sources.is_a?(Array) &&
      result_sources.length == review_sources.length
      raise ValidationError,
        "license review results must cover every source origin exactly"
    end

    reviewed_candidate_count = 0
    open_source_count = 0
    result_sources.each_with_index do |result, offset|
      review = review_sources.fetch(offset)
      origin = review["sourceOrigin"]
      require_hash(result, "license review result for #{origin}")
      unless result.keys.sort == %w[
        attributionCoverage candidateResults declaredLicenseExpressions
        licenseTextCoverage remainingReviewItems resolvedReviewItems reviewState
        sourceOrigin
      ].sort
        raise ValidationError,
          "license review result for #{origin} has unexpected fields"
      end
      unless result["sourceOrigin"] == origin &&
        result["declaredLicenseExpressions"] ==
          review["declaredLicenseExpressions"] &&
        result["reviewState"] == REVIEW_STATE
        raise ValidationError,
          "license review result metadata does not match #{origin}"
      end
      unless COVERAGE.include?(result["licenseTextCoverage"]) &&
        COVERAGE.include?(result["attributionCoverage"])
        raise ValidationError,
          "license review result for #{origin} has invalid coverage"
      end

      resolved = require_string_array(
        result["resolvedReviewItems"],
        "resolvedReviewItems for #{origin}",
        allow_empty: true
      )
      remaining = require_string_array(
        result["remainingReviewItems"],
        "remainingReviewItems for #{origin}",
        allow_empty: true
      )
      expected_items = review["openReviewItems"]
      unless (resolved & remaining).empty? &&
        (resolved + remaining).sort == expected_items.sort
        raise ValidationError,
          "review item disposition for #{origin} is incomplete"
      end
      open_source_count += 1 unless remaining.empty?

      candidates = review["candidateEvidence"]
      validate_candidate_results(result["candidateResults"], candidates, origin)
      reviewed_candidate_count += candidates.length
    end

    unless manifest["reviewedCandidateCount"] == reviewed_candidate_count &&
      manifest["sourceOriginsWithRemainingReviewItems"] == open_source_count
      raise ValidationError,
        "license review result summary counts do not match source results"
    end
    if result_sources.all? do |entry|
      %w[complete not-applicable-no-payload]
        .include?(entry["licenseTextCoverage"])
    end
      raise ValidationError,
        "completeLicenseTextBundlePresent must be revisited for complete coverage"
    end
    if open_source_count.zero?
      raise ValidationError,
        "completePackageNoticeSetPresent must be revisited when no review items remain"
    end

    result_sources
  rescue KeyError => error
    raise ValidationError,
      "license review results are incomplete: #{error.message}"
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    results_path,
      review_path,
      source_acquisition_path,
      source_inventory_path =
      RootFSLicenseReviewResults.resolve_manifest_paths(ARGV)
    review_bytes = Pathname(review_path).binread
    source_acquisition_bytes = Pathname(source_acquisition_path).binread
    source_acquisition =
      RootFSLicenseReviewResults.load_json(
        source_acquisition_path,
        "source acquisition manifest"
      )
    allow_file_urls =
      ENV["POCKETROOT_TEST_ALLOW_FILE_URLS"] == "1" &&
      source_acquisition["testFixture"] == true
    sources = RootFSLicenseReviewResults.validate_manifest(
      RootFSLicenseReviewResults.load_json(
        results_path,
        "license review results"
      ),
      JSON.parse(review_bytes),
      source_acquisition: source_acquisition,
      source_inventory:
        RootFSLicenseReviewResults.load_json(
          source_inventory_path,
          "source inventory"
        ),
      license_review_bytes: review_bytes,
      source_acquisition_bytes: source_acquisition_bytes,
      allow_file_urls: allow_file_urls
    )
    puts "RootFS license review results are valid " \
      "(#{sources.length} source origins)."
  rescue RootFSLicenseReviewResults::ValidationError,
    JSON::ParserError, SystemCallError => error
    warn error.message
    exit 1
  end
end
