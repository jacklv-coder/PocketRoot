#!/usr/bin/env ruby

require "digest"
require "json"
require "pathname"
require "uri"
require_relative "rootfs-license-review-results"

module RootFSLicenseNoticeCandidates
  ARCHIVE_VERSION = "v0.3.3"
  ARCHIVE_SHA256 =
    "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
  STATUS = "candidate-bundle-indexed-engineering-review-required"
  CANDIDATE_STATE = "collected-engineering-review-required"
  SPDX_REVISION = "c4a7237ec8f4654e867546f9f409749300f1bf4c"
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/
  SAFE_COMPONENT_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._+@-]*\z/
  MAX_REMOTE_PAYLOAD_BYTES = 1_048_576
  EXPECTED_OPEN_SOURCE_ORIGINS = %w[
    alpine-baselayout alpine-keys apk-tools busybox ca-certificates musl
    openssl pax-utils
  ].freeze
  EXPECTED_EXISTING_EVIDENCE_FILES = 21
  EXPECTED_REMOTE_PAYLOAD_FILES = 8
  EXPECTED_APORTS_FILES = 46
  PAYLOAD_KINDS = %w[package-attribution spdx-license-text].freeze
  TOP_LEVEL_KEYS = %w[
    archive candidateBundleIndexComplete candidatePayloadCommitted
    engineeringReviewApproved legalReviewApproved licenseReviewResultsSha256
    redistributionApproved remotePayloads schemaVersion sources status
  ].freeze
  SOURCE_KEYS = %w[
    candidateState declaredLicenseExpressions existingEvidencePaths
    referenceLicensePaths remainingReviewItems remoteEvidencePaths sourceOrigin
    supplementalAportsPaths
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

  def require_string(value, label, pattern = nil)
    unless value.is_a?(String) && !value.empty?
      raise ValidationError, "#{label} must be a non-empty string"
    end
    if pattern && !value.match?(pattern)
      raise ValidationError, "#{label} has an invalid format"
    end

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

  def safe_relative_path?(value)
    RootFSLicenseReview.safe_relative_path?(value)
  end

  def require_safe_paths(value, label, allow_empty: false)
    paths = require_string_array(value, label, allow_empty: allow_empty)
    unless paths.all? { |path| safe_relative_path?(path) }
      raise ValidationError, "#{label} contains an unsafe path"
    end

    paths
  end

  def paths_conflict?(left, right)
    left == right ||
      left.start_with?("#{right}/") ||
      right.start_with?("#{left}/")
  end

  def validate_url(value, label, allow_file_urls)
    text = require_string(value, label)
    uri = URI.parse(text)
    allowed_schemes = allow_file_urls ? %w[file https] : %w[https]
    unless allowed_schemes.include?(uri.scheme)
      raise ValidationError,
        "#{label} must use #{allowed_schemes.join(" or ")}"
    end
    if uri.userinfo || uri.fragment
      raise ValidationError,
        "#{label} must not contain credentials or a fragment"
    end
    if uri.scheme == "https" && (!uri.host || uri.host.empty?)
      raise ValidationError, "#{label} must include a host"
    end
    if uri.scheme == "file" &&
      !Pathname(URI.decode_www_form_component(uri.path)).absolute?
      raise ValidationError, "#{label} file path must be absolute"
    end

    text
  rescue URI::InvalidURIError => error
    raise ValidationError, "#{label} is invalid: #{error.message}"
  end

  def identifiers_in_expressions(expressions)
    expressions.flat_map do |expression|
      expression.scan(/[A-Za-z0-9][A-Za-z0-9.+-]*/)
        .reject { |token| %w[AND OR WITH].include?(token) }
    end.uniq.sort
  end

  def validate_remote_payload(payload, offset, allow_file_urls)
    payload = require_hash(payload, "remotePayloads[#{offset}]")
    kind = require_string(payload["kind"], "remotePayloads[#{offset}].kind")
    unless PAYLOAD_KINDS.include?(kind)
      raise ValidationError, "remotePayloads[#{offset}].kind is unsupported"
    end
    common_keys = %w[
      byteCount cacheKey kind outputPath retrievalURLs sha256
    ]
    specific_keys =
      if kind == "spdx-license-text"
        %w[sourceRevision spdxIdentifiers]
      else
        %w[sourceOrigin]
      end
    unless payload.keys.sort == (common_keys + specific_keys).sort
      raise ValidationError,
        "remotePayloads[#{offset}] has unexpected fields"
    end

    urls = require_string_array(
      payload["retrievalURLs"],
      "remotePayloads[#{offset}].retrievalURLs"
    )
    urls.each_with_index do |url, url_offset|
      validate_url(
        url,
        "remotePayloads[#{offset}].retrievalURLs[#{url_offset}]",
        allow_file_urls
      )
    end
    cache_key = require_string(
      payload["cacheKey"],
      "remotePayloads[#{offset}].cacheKey",
      SAFE_COMPONENT_PATTERN
    )
    output_path = require_string(
      payload["outputPath"],
      "remotePayloads[#{offset}].outputPath"
    )
    unless safe_relative_path?(output_path)
      raise ValidationError,
        "remotePayloads[#{offset}].outputPath is unsafe"
    end
    unless payload["byteCount"].is_a?(Integer) &&
      payload["byteCount"].positive? &&
      payload["byteCount"] <= MAX_REMOTE_PAYLOAD_BYTES
      raise ValidationError,
        "remotePayloads[#{offset}].byteCount is invalid"
    end
    require_string(
      payload["sha256"],
      "remotePayloads[#{offset}].sha256",
      SHA256_PATTERN
    )

    if kind == "spdx-license-text"
      identifiers = require_string_array(
        payload["spdxIdentifiers"],
        "remotePayloads[#{offset}].spdxIdentifiers"
      )
      identifiers.each do |identifier|
        require_string(
          identifier,
          "remotePayloads[#{offset}].spdxIdentifiers entry",
          SAFE_COMPONENT_PATTERN
        )
      end
      unless payload["sourceRevision"] == SPDX_REVISION
        raise ValidationError,
          "remotePayloads[#{offset}] does not use the pinned SPDX revision"
      end
      unless output_path.start_with?("licenses/")
        raise ValidationError,
          "remotePayloads[#{offset}] SPDX output must be under licenses/"
      end
    else
      source_origin = require_string(
        payload["sourceOrigin"],
        "remotePayloads[#{offset}].sourceOrigin",
        SAFE_COMPONENT_PATTERN
      )
      unless output_path.start_with?("supplemental/#{source_origin}/")
        raise ValidationError,
          "remotePayloads[#{offset}] package output must be under its source origin"
      end
    end

    [cache_key, output_path]
  end

  def validate_manifest(
    manifest,
    results,
    license_review:,
    source_acquisition:,
    source_inventory:,
    results_bytes:,
    license_review_bytes:,
    source_acquisition_bytes:,
    allow_file_urls: false
  )
    require_hash(manifest, "license/NOTICE candidate manifest")
    require_hash(results, "license review results")
    unless manifest.keys.sort == TOP_LEVEL_KEYS.sort
      raise ValidationError,
        "license/NOTICE candidate manifest has unexpected fields"
    end
    unless manifest["schemaVersion"] == 1 &&
      manifest["archive"] == {
        "version" => ARCHIVE_VERSION,
        "sha256" => ARCHIVE_SHA256
      }
      raise ValidationError,
        "license/NOTICE candidates do not match the pinned archive"
    end
    unless manifest["licenseReviewResultsSha256"] ==
      Digest::SHA256.hexdigest(results_bytes) &&
      results.eql?(JSON.parse(results_bytes))
      raise ValidationError,
        "license/NOTICE candidates do not match LICENSE-REVIEW-RESULTS.json bytes"
    end

    begin
      result_sources = RootFSLicenseReviewResults.validate_manifest(
        results,
        license_review,
        source_acquisition: source_acquisition,
        source_inventory: source_inventory,
        license_review_bytes: license_review_bytes,
        source_acquisition_bytes: source_acquisition_bytes,
        allow_file_urls: allow_file_urls
      )
    rescue RootFSLicenseReviewResults::ValidationError,
      JSON::ParserError => error
      raise ValidationError,
        "license/NOTICE candidates reference invalid review results: #{error.message}"
    end
    unless manifest["status"] == STATUS &&
      manifest["candidateBundleIndexComplete"] == true &&
      manifest["candidatePayloadCommitted"] == false &&
      manifest["engineeringReviewApproved"] == false &&
      manifest["legalReviewApproved"] == false &&
      manifest["redistributionApproved"] == false
      raise ValidationError,
        "license/NOTICE candidates do not preserve the open release gates"
    end

    remote_payloads = manifest["remotePayloads"]
    unless remote_payloads.is_a?(Array) &&
      remote_payloads.length == EXPECTED_REMOTE_PAYLOAD_FILES
      raise ValidationError,
        "remotePayloads must contain exactly " \
        "#{EXPECTED_REMOTE_PAYLOAD_FILES} entries"
    end
    cache_keys = []
    remote_output_paths = []
    remote_payloads.each_with_index do |payload, offset|
      cache_key, output_path =
        validate_remote_payload(payload, offset, allow_file_urls)
      cache_keys << cache_key
      remote_output_paths << output_path
    end
    unless cache_keys.uniq.length == cache_keys.length &&
      remote_output_paths.uniq.length == remote_output_paths.length
      raise ValidationError,
        "remote payload cache keys and output paths must be unique"
    end

    open_results = result_sources.select do |source|
      !source.fetch("remainingReviewItems").empty?
    end
    all_existing_paths =
      result_sources.flat_map do |source|
        source.fetch("candidateResults").map do |candidate|
          candidate.fetch("outputPath")
        end
      end
    existing_evidence =
      license_review.fetch("sources").flat_map do |source|
        source.fetch("candidateEvidence")
      end.to_h do |candidate|
        [
          candidate.fetch("outputPath"),
          {
            "byteCount" => candidate.fetch("byteCount"),
            "sha256" => candidate.fetch("sha256")
          }
        ]
      end
    sources = manifest["sources"]
    unless open_results.map { |source| source.fetch("sourceOrigin") } ==
      EXPECTED_OPEN_SOURCE_ORIGINS &&
      sources.is_a?(Array) &&
      sources.length == EXPECTED_OPEN_SOURCE_ORIGINS.length
      raise ValidationError,
        "license/NOTICE candidates must cover every open source origin"
    end

    license_paths_by_identifier = {}
    package_remote_paths = Hash.new { |origins, origin| origins[origin] = [] }
    remote_payloads.each do |payload|
      if payload["kind"] == "spdx-license-text"
        payload.fetch("spdxIdentifiers").each do |identifier|
          if license_paths_by_identifier.key?(identifier)
            raise ValidationError,
              "duplicate SPDX identifier mapping: #{identifier}"
          end
          license_paths_by_identifier[identifier] = payload.fetch("outputPath")
        end
      else
        package_remote_paths[payload.fetch("sourceOrigin")] <<
          payload.fetch("outputPath")
      end
    end

    used_existing_paths = []
    used_aports_paths = []
    used_remote_paths = []
    used_license_paths = []
    sources.each_with_index do |source, offset|
      expected = open_results.fetch(offset)
      origin = expected.fetch("sourceOrigin")
      source = require_hash(source, "sources[#{offset}]")
      unless source.keys.sort == SOURCE_KEYS.sort
        raise ValidationError, "candidate source #{origin} has unexpected fields"
      end
      unless source["sourceOrigin"] == origin &&
        source["declaredLicenseExpressions"] ==
          expected["declaredLicenseExpressions"] &&
        source["remainingReviewItems"] == expected["remainingReviewItems"] &&
        source["candidateState"] == CANDIDATE_STATE
        raise ValidationError,
          "candidate source metadata does not match #{origin}"
      end

      existing_paths = require_safe_paths(
        source["existingEvidencePaths"],
        "existingEvidencePaths for #{origin}"
      )
      expected_existing =
        expected.fetch("candidateResults")
          .map { |candidate| candidate.fetch("outputPath") }
          .sort
      unless existing_paths.sort == expected_existing
        raise ValidationError,
          "existing evidence paths do not match review results for #{origin}"
      end

      reference_paths = require_safe_paths(
        source["referenceLicensePaths"],
        "referenceLicensePaths for #{origin}"
      )
      identifiers =
        identifiers_in_expressions(source.fetch("declaredLicenseExpressions"))
      expected_reference_paths = identifiers.map do |identifier|
        license_paths_by_identifier.fetch(identifier) do
          raise ValidationError,
            "no reference license text is indexed for #{identifier}"
        end
      end.uniq.sort
      unless reference_paths.sort == expected_reference_paths
        raise ValidationError,
          "reference license paths do not cover declarations for #{origin}"
      end

      aports_paths = require_safe_paths(
        source["supplementalAportsPaths"],
        "supplementalAportsPaths for #{origin}",
        allow_empty: true
      )
      unless aports_paths.all? { |path| path.start_with?("aports/#{origin}/") }
        raise ValidationError,
          "supplemental aports paths do not match #{origin}"
      end

      remote_paths = require_safe_paths(
        source["remoteEvidencePaths"],
        "remoteEvidencePaths for #{origin}",
        allow_empty: true
      )
      unless remote_paths.sort == package_remote_paths.fetch(origin, []).sort
        raise ValidationError,
          "remote evidence paths do not match #{origin}"
      end

      used_existing_paths.concat(existing_paths)
      used_aports_paths.concat(aports_paths)
      used_remote_paths.concat(remote_paths)
      used_license_paths.concat(reference_paths)
    end

    unless used_existing_paths.uniq.length == used_existing_paths.length &&
      all_existing_paths.length == EXPECTED_EXISTING_EVIDENCE_FILES &&
      used_aports_paths.uniq.length == used_aports_paths.length &&
      used_aports_paths.length == EXPECTED_APORTS_FILES &&
      used_remote_paths.sort ==
        package_remote_paths.values.flatten.sort &&
      used_license_paths.uniq.sort == license_paths_by_identifier.values.uniq.sort
      raise ValidationError,
        "license/NOTICE candidate path coverage is incomplete or duplicated"
    end
    materialized_paths =
      all_existing_paths +
      used_aports_paths.map { |path| "supplemental/#{path}" } +
      remote_output_paths
    if materialized_paths.combination(2).any? do |left, right|
      paths_conflict?(left, right)
    end
      raise ValidationError,
        "license/NOTICE candidate output paths overlap"
    end

    {
      sources: sources,
      remote_payloads: remote_payloads,
      existing_evidence_paths: all_existing_paths,
      existing_evidence: existing_evidence,
      aports_paths: used_aports_paths
    }
  rescue KeyError => error
    raise ValidationError,
      "license/NOTICE candidates are incomplete: #{error.message}"
  end

  def resolve_manifest_paths(arguments)
    unless arguments.length <= 5
      raise ValidationError,
        "usage: rootfs-license-notice-candidates.rb " \
        "[CANDIDATES RESULTS REVIEW SOURCE_ACQUISITION SOURCE_INVENTORY]"
    end
    directory =
      Pathname(
        arguments.fetch(
          0,
          "Compliance/RootFS/v0.3.3/LICENSE-NOTICE-CANDIDATES.json"
        )
      ).dirname

    [
      arguments.fetch(
        0,
        directory.join("LICENSE-NOTICE-CANDIDATES.json").to_s
      ),
      arguments.fetch(1, directory.join("LICENSE-REVIEW-RESULTS.json").to_s),
      arguments.fetch(2, directory.join("LICENSE-REVIEW.json").to_s),
      arguments.fetch(3, directory.join("SOURCE-ACQUISITION.json").to_s),
      arguments.fetch(4, directory.join("SOURCE-INVENTORY.json").to_s)
    ]
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    candidate_path,
      results_path,
      review_path,
      source_acquisition_path,
      source_inventory_path =
      RootFSLicenseNoticeCandidates.resolve_manifest_paths(ARGV)
    results_bytes = Pathname(results_path).binread
    review_bytes = Pathname(review_path).binread
    source_acquisition_bytes = Pathname(source_acquisition_path).binread
    source_acquisition = JSON.parse(source_acquisition_bytes)
    allow_file_urls =
      ENV["POCKETROOT_TEST_ALLOW_FILE_URLS"] == "1" &&
      source_acquisition["testFixture"] == true
    validated = RootFSLicenseNoticeCandidates.validate_manifest(
      RootFSLicenseNoticeCandidates.load_json(
        candidate_path,
        "license/NOTICE candidate manifest"
      ),
      JSON.parse(results_bytes),
      license_review: JSON.parse(review_bytes),
      source_acquisition: source_acquisition,
      source_inventory:
        RootFSLicenseNoticeCandidates.load_json(
          source_inventory_path,
          "source inventory"
        ),
      results_bytes: results_bytes,
      license_review_bytes: review_bytes,
      source_acquisition_bytes: source_acquisition_bytes,
      allow_file_urls: allow_file_urls
    )
    puts "RootFS license/NOTICE candidate manifest is valid " \
      "(#{validated.fetch(:sources).length} open source origins, " \
      "#{validated.fetch(:remote_payloads).length} remote payloads, " \
      "#{validated.fetch(:aports_paths).length} aports files)."
  rescue RootFSLicenseNoticeCandidates::ValidationError,
    JSON::ParserError, SystemCallError => error
    warn error.message
    exit 1
  end
end
