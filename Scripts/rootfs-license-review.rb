#!/usr/bin/env ruby

require "digest"
require "json"
require "pathname"

module RootFSLicenseReview
  ARCHIVE_VERSION = "v0.3.3"
  ARCHIVE_SHA256 =
    "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/
  SAFE_COMPONENT_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._+@-]*\z/
  SOURCE_KINDS = %w[aports-file distfile-member].freeze
  EVIDENCE_KINDS = %w[
    attribution
    inline-license-notice
    license-declaration
    license-text
  ].freeze
  STATUS = "candidate-evidence-indexed-external-review-required"

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

  def safe_relative_path?(value)
    return false unless value.is_a?(String) && !value.empty?
    return false if value.start_with?("/", "-") || value.include?("\\") || value.include?("\0")

    components = value.split("/", -1)
    components.all? do |component|
      component != "." &&
        component != ".." &&
        SAFE_COMPONENT_PATTERN.match?(component)
    end
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

  def validate_candidate(candidate, origin, distfiles)
    require_hash(candidate, "candidate evidence for #{origin}")
    source_kind = candidate["sourceKind"]
    unless SOURCE_KINDS.include?(source_kind)
      raise ValidationError, "candidate evidence for #{origin} has invalid sourceKind"
    end

    output_path = candidate["outputPath"]
    unless safe_relative_path?(output_path) &&
      output_path.start_with?("evidence/#{origin}/")
      raise ValidationError, "candidate evidence for #{origin} has unsafe outputPath"
    end
    byte_count = candidate["byteCount"]
    unless byte_count.is_a?(Integer) && byte_count.positive? && byte_count <= 8 * 1_024 * 1_024
      raise ValidationError, "candidate evidence for #{origin} has invalid byteCount"
    end
    unless SHA256_PATTERN.match?(candidate["sha256"].to_s)
      raise ValidationError, "candidate evidence for #{origin} has invalid sha256"
    end
    evidence_kinds = require_string_array(
      candidate["evidenceKinds"],
      "candidate evidenceKinds for #{origin}"
    )
    unless (evidence_kinds - EVIDENCE_KINDS).empty?
      raise ValidationError, "candidate evidence for #{origin} has invalid evidenceKinds"
    end
    unless candidate["reviewState"] == "unreviewed-candidate"
      raise ValidationError, "candidate evidence for #{origin} must remain unreviewed"
    end

    case source_kind
    when "aports-file"
      expected_prefix = "aports/#{origin}/"
      source_path = candidate["path"]
      unless safe_relative_path?(source_path) && source_path.start_with?(expected_prefix)
        raise ValidationError, "candidate evidence for #{origin} has invalid aports path"
      end
      unless candidate.keys.sort ==
        %w[
          byteCount evidenceKinds outputPath path reviewState sha256 sourceKind
        ].sort
        raise ValidationError, "candidate evidence for #{origin} has unexpected fields"
      end
    when "distfile-member"
      distfile = candidate["distfile"]
      member = candidate["member"]
      unless safe_relative_path?(distfile) && distfiles.include?(distfile)
        raise ValidationError, "candidate evidence for #{origin} references an unknown distfile"
      end
      unless safe_relative_path?(member)
        raise ValidationError, "candidate evidence for #{origin} has an unsafe archive member"
      end
      unless candidate.keys.sort ==
        %w[
          byteCount distfile evidenceKinds member outputPath reviewState sha256
          sourceKind
        ].sort
        raise ValidationError, "candidate evidence for #{origin} has unexpected fields"
      end
    end

    candidate
  end

  def validate_manifest(manifest, source_acquisition, source_inventory, source_acquisition_bytes:)
    require_hash(manifest, "license review manifest")
    require_hash(source_acquisition, "source acquisition manifest")
    require_hash(source_inventory, "source inventory")

    unless manifest["schemaVersion"] == 1
      raise ValidationError, "license review manifest.schemaVersion must be 1"
    end
    archive = require_hash(manifest["archive"], "license review manifest.archive")
    unless archive == {
      "version" => ARCHIVE_VERSION,
      "sha256" => ARCHIVE_SHA256
    }
      raise ValidationError, "license review manifest does not match the pinned archive"
    end
    unless manifest["sourceAcquisitionSha256"] ==
      Digest::SHA256.hexdigest(source_acquisition_bytes)
      raise ValidationError, "license review manifest does not match source acquisition bytes"
    end
    unless manifest["status"] == STATUS &&
      manifest["completeLicenseTextBundlePresent"] == false &&
      manifest["completePackageNoticeSetPresent"] == false &&
      manifest["legalReviewApproved"] == false &&
      manifest["redistributionApproved"] == false
      raise ValidationError, "license review manifest does not preserve open release gates"
    end

    source_entries = source_acquisition["sources"]
    inventory_entries = source_inventory["sourceOrigins"]
    review_entries = manifest["sources"]
    unless source_entries.is_a?(Array) &&
      inventory_entries.is_a?(Array) &&
      review_entries.is_a?(Array)
      raise ValidationError, "license review inputs must contain source arrays"
    end

    source_by_origin = source_entries.to_h do |entry|
      [entry["sourceOrigin"], entry]
    end
    inventory_by_origin = inventory_entries.to_h do |entry|
      [entry["sourceOrigin"], entry]
    end
    review_origins = review_entries.map { |entry| entry["sourceOrigin"] }
    expected_origins = source_entries.map { |entry| entry["sourceOrigin"] }
    unless review_origins == expected_origins &&
      review_origins.uniq.length == review_origins.length &&
      inventory_by_origin.keys.sort == expected_origins.sort
      raise ValidationError, "license review manifest must cover every source origin exactly"
    end

    output_paths = []
    review_entries.each do |entry|
      origin = entry["sourceOrigin"]
      require_hash(entry, "license review source #{origin}")
      source = source_by_origin.fetch(origin)
      inventory = inventory_by_origin.fetch(origin)
      unless entry["binaryPackages"] == inventory["binaryPackages"] &&
        entry["declaredLicenseExpressions"] == inventory["declaredLicenseExpressions"]
        raise ValidationError, "license review metadata does not match source inventory for #{origin}"
      end
      unless entry["reviewState"] == "engineering-indexed-legal-review-open"
        raise ValidationError, "license review state must remain open for #{origin}"
      end
      require_string_array(entry["openReviewItems"], "openReviewItems for #{origin}")
      candidates = entry["candidateEvidence"]
      unless candidates.is_a?(Array) && !candidates.empty?
        raise ValidationError, "candidateEvidence for #{origin} must not be empty"
      end
      distfiles = source.fetch("distfiles").map { |distfile| distfile.fetch("filename") }
      candidates.each do |candidate|
        validate_candidate(candidate, origin, distfiles)
        output_paths << candidate.fetch("outputPath")
      end
      unless entry.keys.sort ==
        %w[
          binaryPackages candidateEvidence declaredLicenseExpressions
          openReviewItems reviewState sourceOrigin
        ].sort
        raise ValidationError, "license review source #{origin} has unexpected fields"
      end
    end
    unless output_paths.uniq.length == output_paths.length
      raise ValidationError, "license review candidate output paths must be unique"
    end

    review_entries
  rescue KeyError => error
    raise ValidationError, "license review manifest is incomplete: #{error.message}"
  end
end
