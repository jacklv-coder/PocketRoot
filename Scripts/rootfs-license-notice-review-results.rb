#!/usr/bin/env ruby

require "digest"
require "find"
require "json"
require "optparse"
require "pathname"
require_relative "rootfs-license-notice-candidates"

module RootFSLicenseNoticeReviewResults
  DEFAULT_MANIFEST_DIRECTORY = Pathname("Compliance/RootFS/v0.3.3")
  ARCHIVE_VERSION = "v0.3.3"
  ARCHIVE_SHA256 =
    "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
  STATUS = "candidate-payloads-engineering-reviewed-open-release-gates"
  REVIEW_STATE =
    "candidate-payloads-engineering-reviewed-legal-review-open"
  REVIEW_CONCLUSIONS = %w[
    additional-package-material-required
    candidate-material-complete-engineering-only
  ].freeze
  COVERAGE = %w[complete partial reference-only].freeze
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/
  CANDIDATE_PAYLOAD_TREE_FORMAT = "sha256-path-lines-v1"
  EXPECTED_REVIEWED_PAYLOAD_FILES = 78
  MAX_REVIEWED_PAYLOAD_BYTES = 8 * 1_024 * 1_024
  TOP_LEVEL_KEYS = %w[
    allIndexedCandidatePayloadsReviewed archive candidateManifestSha256
    candidatePayloadTreeFormat candidatePayloadTreeSha256
    completePackageLicenseNoticeSetPresent engineeringReviewCompleted
    legalReviewApproved redistributionApproved referenceLicenseTextsReviewed
    reviewedClosedOriginEvidenceCount reviewedPayloadFileCount schemaVersion
    sourceOriginsWithRemainingReviewItems sources status
  ].freeze
  SOURCE_KEYS = %w[
    attributionCoverage declaredLicenseExpressions engineeringConclusion
    licenseTextCoverage remainingReviewItems resolvedReviewItems
    reviewState reviewedExistingEvidenceCount reviewedReferenceLicenseCount
    reviewedRemoteEvidenceCount reviewedSupplementalAportsCount sourceOrigin
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

  def parse_options(arguments)
    options = {}
    parser = OptionParser.new do |commands|
      commands.banner =
        "Usage: ruby Scripts/rootfs-license-notice-review-results.rb " \
        "[options] [RESULTS CANDIDATES PRIOR_RESULTS REVIEW " \
        "SOURCE_ACQUISITION SOURCE_INVENTORY]"
      commands.on(
        "--bundle DIR",
        "Verify the reviewed candidate payload directory"
      ) do |value|
        options[:bundle] = value
      end
    end
    remaining = arguments.dup
    parser.parse!(remaining)
    [options, resolve_manifest_paths(remaining)]
  end

  def resolve_manifest_paths(arguments)
    unless arguments.length <= 6
      raise ValidationError,
        "expected at most six manifest paths"
    end
    directory =
      Pathname(
        arguments.fetch(
          0,
          DEFAULT_MANIFEST_DIRECTORY
            .join("LICENSE-NOTICE-REVIEW-RESULTS.json")
            .to_s
        )
      ).dirname

    [
      arguments.fetch(
        0,
        directory.join("LICENSE-NOTICE-REVIEW-RESULTS.json").to_s
      ),
      arguments.fetch(
        1,
        directory.join("LICENSE-NOTICE-CANDIDATES.json").to_s
      ),
      arguments.fetch(
        2,
        directory.join("LICENSE-REVIEW-RESULTS.json").to_s
      ),
      arguments.fetch(3, directory.join("LICENSE-REVIEW.json").to_s),
      arguments.fetch(
        4,
        directory.join("SOURCE-ACQUISITION.json").to_s
      ),
      arguments.fetch(5, directory.join("SOURCE-INVENTORY.json").to_s)
    ]
  end

  def validate_manifest(
    manifest,
    candidates,
    prior_results:,
    license_review:,
    source_acquisition:,
    source_inventory:,
    candidate_bytes:,
    prior_results_bytes:,
    license_review_bytes:,
    source_acquisition_bytes:,
    allow_file_urls: false
  )
    require_hash(manifest, "license/NOTICE candidate review results")
    require_hash(candidates, "license/NOTICE candidate manifest")
    unless manifest.keys.sort == TOP_LEVEL_KEYS.sort
      raise ValidationError,
        "license/NOTICE candidate review results have unexpected fields"
    end
    unless manifest["schemaVersion"] == 1 &&
      manifest["archive"] == {
        "version" => ARCHIVE_VERSION,
        "sha256" => ARCHIVE_SHA256
      }
      raise ValidationError,
        "license/NOTICE candidate review results do not match the pinned archive"
    end
    unless candidates.eql?(JSON.parse(candidate_bytes)) &&
      manifest["candidateManifestSha256"] ==
        Digest::SHA256.hexdigest(candidate_bytes)
      raise ValidationError,
        "license/NOTICE candidate review results do not match candidate manifest bytes"
    end

    validated_candidates =
      begin
        RootFSLicenseNoticeCandidates.validate_manifest(
          candidates,
          prior_results,
          license_review: license_review,
          source_acquisition: source_acquisition,
          source_inventory: source_inventory,
          results_bytes: prior_results_bytes,
          license_review_bytes: license_review_bytes,
          source_acquisition_bytes: source_acquisition_bytes,
          allow_file_urls: allow_file_urls
        )
      rescue RootFSLicenseNoticeCandidates::ValidationError,
        JSON::ParserError => error
        raise ValidationError,
          "candidate review results reference invalid inputs: #{error.message}"
      end

    unless manifest["status"] == STATUS &&
      manifest["engineeringReviewCompleted"] == true &&
      manifest["allIndexedCandidatePayloadsReviewed"] == true &&
      manifest["referenceLicenseTextsReviewed"] == true &&
      manifest["completePackageLicenseNoticeSetPresent"] == false &&
      manifest["legalReviewApproved"] == false &&
      manifest["redistributionApproved"] == false &&
      manifest["candidatePayloadTreeFormat"] ==
        CANDIDATE_PAYLOAD_TREE_FORMAT &&
      manifest["candidatePayloadTreeSha256"].is_a?(String) &&
      manifest["candidatePayloadTreeSha256"].match?(SHA256_PATTERN)
      raise ValidationError,
        "license/NOTICE candidate review results do not preserve open release gates"
    end

    candidate_sources = validated_candidates.fetch(:sources)
    result_sources = manifest["sources"]
    unless result_sources.is_a?(Array) &&
      result_sources.length == candidate_sources.length
      raise ValidationError,
        "candidate review results must cover every open source origin"
    end

    open_source_count = 0
    reviewed_payload_references = []
    result_sources.each_with_index do |result, offset|
      candidate = candidate_sources.fetch(offset)
      origin = candidate.fetch("sourceOrigin")
      result = require_hash(result, "candidate review result for #{origin}")
      unless result.keys.sort == SOURCE_KEYS.sort
        raise ValidationError,
          "candidate review result for #{origin} has unexpected fields"
      end
      unless result["sourceOrigin"] == origin &&
        result["declaredLicenseExpressions"] ==
          candidate["declaredLicenseExpressions"] &&
        result["reviewState"] == REVIEW_STATE &&
        COVERAGE.include?(result["licenseTextCoverage"]) &&
        COVERAGE.include?(result["attributionCoverage"]) &&
        REVIEW_CONCLUSIONS.include?(result["engineeringConclusion"])
        raise ValidationError,
          "candidate review result metadata does not match #{origin}"
      end

      expected_counts = {
        "reviewedExistingEvidenceCount" =>
          candidate.fetch("existingEvidencePaths").length,
        "reviewedReferenceLicenseCount" =>
          candidate.fetch("referenceLicensePaths").length,
        "reviewedSupplementalAportsCount" =>
          candidate.fetch("supplementalAportsPaths").length,
        "reviewedRemoteEvidenceCount" =>
          candidate.fetch("remoteEvidencePaths").length
      }
      unless expected_counts.all? do |key, expected|
        result[key].is_a?(Integer) && result[key] == expected
      end
        raise ValidationError,
          "candidate review result counts do not match #{origin}"
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
      expected_items = candidate.fetch("remainingReviewItems")
      unless (resolved & remaining).empty? &&
        (resolved + remaining).sort == expected_items.sort
        raise ValidationError,
          "candidate review item disposition for #{origin} is incomplete"
      end
      expected_conclusion =
        if remaining.empty?
          "candidate-material-complete-engineering-only"
        else
          "additional-package-material-required"
        end
      unless result["engineeringConclusion"] == expected_conclusion
        raise ValidationError,
          "candidate review conclusion does not match open items for #{origin}"
      end
      open_source_count += 1 unless remaining.empty?
      reviewed_payload_references.concat(
        candidate.fetch("existingEvidencePaths"),
        candidate.fetch("referenceLicensePaths"),
        candidate.fetch("supplementalAportsPaths"),
        candidate.fetch("remoteEvidencePaths")
      )
    end

    unless manifest["sourceOriginsWithRemainingReviewItems"] ==
      open_source_count
      raise ValidationError,
        "candidate review open-source summary count does not match source results"
    end
    unique_payload_count =
      validated_candidates.fetch(:existing_evidence_paths).length +
      validated_candidates.fetch(:aports_paths).length +
      validated_candidates.fetch(:remote_payloads).length
    open_existing_paths =
      candidate_sources.flat_map do |source|
        source.fetch("existingEvidencePaths")
      end
    closed_origin_evidence_count =
      validated_candidates.fetch(:existing_evidence_paths).length -
      open_existing_paths.length
    unless unique_payload_count == EXPECTED_REVIEWED_PAYLOAD_FILES &&
      manifest["reviewedPayloadFileCount"] == unique_payload_count &&
      manifest["reviewedClosedOriginEvidenceCount"] ==
        closed_origin_evidence_count &&
      reviewed_payload_references.uniq.length +
        closed_origin_evidence_count == unique_payload_count
      raise ValidationError,
        "candidate review payload counts do not cover the indexed payload set"
    end
    if open_source_count.zero?
      raise ValidationError,
        "completePackageLicenseNoticeSetPresent must be revisited when no items remain"
    end

    validated_candidates
  rescue KeyError => error
    raise ValidationError,
      "license/NOTICE candidate review results are incomplete: #{error.message}"
  end

  def expected_payloads(validated_candidates)
    expected = {}
    validated_candidates.fetch(:existing_evidence).each do |path, metadata|
      expected[path] = metadata.fetch("sha256")
    end
    validated_candidates.fetch(:remote_payloads).each do |payload|
      expected[payload.fetch("outputPath")] = payload.fetch("sha256")
    end
    validated_candidates.fetch(:aports_paths).each do |path|
      expected["supplemental/#{path}"] = nil
    end
    expected
  end

  def verify_reviewed_bundle(path, validated_candidates, expected_tree_sha256)
    root = Pathname(path)
    unless root.absolute? && root.directory? && !root.symlink?
      raise ValidationError,
        "reviewed bundle must be an absolute real directory"
    end
    root = root.realpath
    payloads = expected_payloads(validated_candidates)
    actual_paths = []
    payload_directories = %w[evidence licenses supplemental]
    root.find do |entry|
      next if entry == root

      relative = entry.relative_path_from(root).to_s
      stat = entry.lstat
      if stat.symlink? || (!stat.directory? && !stat.file?)
        raise ValidationError,
          "reviewed bundle contains a link or special node: #{relative}"
      end
      if stat.file? && payload_directories.include?(relative.split("/", 2).first)
        actual_paths << relative
      end
    end
    payload_directories.each do |directory|
      subtree = root.join(directory)
      unless subtree.directory? && !subtree.symlink?
        raise ValidationError,
          "reviewed bundle is missing #{directory}/"
      end
    end
    unless actual_paths.sort == payloads.keys.sort
      raise ValidationError,
        "reviewed bundle payload path set does not match the candidate index"
    end

    lines = actual_paths.sort.map do |relative|
      pathname = root.join(relative)
      if pathname.size > MAX_REVIEWED_PAYLOAD_BYTES
        raise ValidationError,
          "reviewed bundle payload exceeds size limit: #{relative}"
      end
      digest = Digest::SHA256.file(pathname).hexdigest
      expected_digest = payloads.fetch(relative)
      if expected_digest && digest != expected_digest
        raise ValidationError,
          "reviewed bundle payload digest mismatch: #{relative}"
      end
      "#{digest}  #{relative}\n"
    end
    actual_tree_sha256 = Digest::SHA256.hexdigest(lines.join)
    unless actual_tree_sha256 == expected_tree_sha256
      raise ValidationError,
        "reviewed bundle payload tree digest mismatch: expected " \
        "#{expected_tree_sha256}, got #{actual_tree_sha256}"
    end

    actual_paths.length
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options, paths =
      RootFSLicenseNoticeReviewResults.parse_options(ARGV)
    results_path,
      candidate_path,
      prior_results_path,
      review_path,
      source_acquisition_path,
      source_inventory_path = paths
    candidate_bytes = Pathname(candidate_path).binread
    prior_results_bytes = Pathname(prior_results_path).binread
    license_review_bytes = Pathname(review_path).binread
    source_acquisition_bytes = Pathname(source_acquisition_path).binread
    source_acquisition = JSON.parse(source_acquisition_bytes)
    allow_file_urls =
      ENV["POCKETROOT_TEST_ALLOW_FILE_URLS"] == "1" &&
      source_acquisition["testFixture"] == true
    manifest =
      RootFSLicenseNoticeReviewResults.load_json(
        results_path,
        "license/NOTICE candidate review results"
      )
    validated =
      RootFSLicenseNoticeReviewResults.validate_manifest(
        manifest,
        JSON.parse(candidate_bytes),
        prior_results: JSON.parse(prior_results_bytes),
        license_review: JSON.parse(license_review_bytes),
        source_acquisition: source_acquisition,
        source_inventory:
          RootFSLicenseNoticeReviewResults.load_json(
            source_inventory_path,
            "source inventory"
          ),
        candidate_bytes: candidate_bytes,
        prior_results_bytes: prior_results_bytes,
        license_review_bytes: license_review_bytes,
        source_acquisition_bytes: source_acquisition_bytes,
        allow_file_urls: allow_file_urls
      )
    if options[:bundle]
      count =
        RootFSLicenseNoticeReviewResults.verify_reviewed_bundle(
          options.fetch(:bundle),
          validated,
          manifest.fetch("candidatePayloadTreeSha256")
        )
      puts "Verified #{count} reviewed RootFS license/NOTICE candidate payloads."
    else
      puts "RootFS license/NOTICE candidate review results are valid " \
        "(#{validated.fetch(:sources).length} source origins)."
    end
  rescue RootFSLicenseNoticeReviewResults::ValidationError,
    JSON::ParserError, KeyError, OptionParser::ParseError,
    SystemCallError => error
    warn error.message
    exit 1
  end
end
