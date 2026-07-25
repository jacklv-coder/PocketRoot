# frozen_string_literal: true

require "pathname"
require "uri"

module RootFSSourceAcquisition
  ROOTFS_VERSION = "v0.3.3"
  ROOTFS_SHA256 =
    "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
  CANONICAL_TREE_FORMAT = "typed-path-mode-sha256-v1"
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/
  SHA512_PATTERN = /\A[0-9a-f]{128}\z/
  COMMIT_PATTERN = /\A[0-9a-f]{40}\z/
  SAFE_COMPONENT_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._+-]*\z/
  EXPECTED_DISTFILES = {
    "alpine-baselayout" => %w[protocols-6.4 services-6.4],
    "alpine-keys" => [],
    "apk-tools" => %w[apk-tools-v2.14.0.tar.gz],
    "busybox" => %w[busybox-1.36.1.tar.bz2],
    "ca-certificates" => %w[ca-certificates-20230506.tar.bz2],
    "libc-dev" => [],
    "musl" => %w[musl-83b858f83b658bd34eca5d8ad4d145f673ae7e5e.tar.gz],
    "openssl" => %w[openssl-3.1.4.tar.gz],
    "pax-utils" => %w[pax-utils-1.3.7.tar.xz],
    "zlib" => %w[zlib-1.3.1.tar.gz]
  }.freeze

  class ValidationError < StandardError
  end

  module_function

  def validate_manifest(manifest, source_inventory, allow_file_urls: false)
    require_hash(manifest, "manifest")
    require_hash(source_inventory, "source inventory")
    raise ValidationError, "manifest.schemaVersion must be 1" unless manifest["schemaVersion"] == 1
    unless manifest["aportsCanonicalTreeFormat"] == CANONICAL_TREE_FORMAT
      raise ValidationError,
        "manifest.aportsCanonicalTreeFormat must be #{CANONICAL_TREE_FORMAT}"
    end
    unless manifest["bundleStatus"] == "external-materialization-required"
      raise ValidationError,
        "manifest.bundleStatus must remain external-materialization-required"
    end
    unless manifest["redistributionApproved"] == false
      raise ValidationError, "manifest must not claim redistribution approval"
    end
    validate_archive_identity(manifest, "manifest")
    validate_archive_identity(source_inventory, "source inventory")

    inventory_sources = require_array(
      source_inventory["sourceOrigins"],
      "source inventory.sourceOrigins"
    )
    expected = inventory_sources.to_h do |entry|
      entry = require_hash(entry, "source inventory source")
      origin = safe_component(entry["sourceOrigin"], "source inventory sourceOrigin")
      [
        origin,
        {
          "aportsCommit" => require_string(
            entry["aportsCommit"],
            "#{origin}.aportsCommit",
            COMMIT_PATTERN
          ),
          "binaryPackages" => require_array(
            entry["binaryPackages"],
            "#{origin}.binaryPackages"
          ).map { |item| safe_component(item, "#{origin}.binaryPackages item") }.sort,
          "declaredLicenseExpressions" => require_array(
            entry["declaredLicenseExpressions"],
            "#{origin}.declaredLicenseExpressions"
          ).map do |item|
            require_string(item, "#{origin}.declaredLicenseExpressions item")
          end.sort
        }
      ]
    end
    if expected.length != inventory_sources.length
      raise ValidationError, "source inventory contains duplicate source origins"
    end

    manifest_sources = require_array(manifest["sources"], "manifest.sources")
    actual = {}
    manifest_sources.each_with_index do |entry, index|
      entry = require_hash(entry, "manifest.sources[#{index}]")
      origin = safe_component(
        entry["sourceOrigin"],
        "manifest.sources[#{index}].sourceOrigin"
      )
      raise ValidationError, "duplicate source origin: #{origin}" if actual.key?(origin)

      commit = require_string(
        entry["aportsCommit"],
        "#{origin}.aportsCommit",
        COMMIT_PATTERN
      )
      packages = require_array(entry["binaryPackages"], "#{origin}.binaryPackages")
        .map { |item| safe_component(item, "#{origin}.binaryPackages item") }
        .sort
      expressions = require_array(
        entry["declaredLicenseExpressions"],
        "#{origin}.declaredLicenseExpressions"
      ).map do |item|
        require_string(item, "#{origin}.declaredLicenseExpressions item")
      end.sort

      snapshot = require_hash(entry["aportsSnapshot"], "#{origin}.aportsSnapshot")
      snapshot_path = require_string(
        snapshot["path"],
        "#{origin}.aportsSnapshot.path"
      )
      expected_path = "main/#{origin}"
      unless snapshot_path == expected_path
        raise ValidationError,
          "#{origin}.aportsSnapshot.path must be #{expected_path}"
      end
      validate_url(
        snapshot["url"],
        "#{origin}.aportsSnapshot.url",
        allow_file_urls
      )
      unless allow_file_urls
        expected_snapshot_url =
          "https://gitlab.alpinelinux.org/api/v4/projects/alpine%2Faports/" \
          "repository/archive.tar.gz?sha=#{commit}&path=main%2F#{origin}"
        unless snapshot["url"] == expected_snapshot_url
          raise ValidationError,
            "#{origin}.aportsSnapshot.url does not match its origin and commit"
        end
      end
      require_string(
        snapshot["canonicalTreeSha256"],
        "#{origin}.aportsSnapshot.canonicalTreeSha256",
        SHA256_PATTERN
      )
      require_string(
        snapshot["sha512"],
        "#{origin}.aportsSnapshot.sha512",
        SHA512_PATTERN
      )
      unless snapshot["regularFileCount"].is_a?(Integer) &&
        snapshot["regularFileCount"].positive?
        raise ValidationError,
          "#{origin}.aportsSnapshot.regularFileCount must be positive"
      end

      distfile_names = {}
      require_array(entry["distfiles"], "#{origin}.distfiles")
        .each_with_index do |distfile, offset|
          distfile = require_hash(distfile, "#{origin}.distfiles[#{offset}]")
          filename = safe_component(
            distfile["filename"],
            "#{origin}.distfiles[#{offset}].filename"
          )
          if distfile_names[filename]
            raise ValidationError,
              "#{origin} contains duplicate distfile #{filename}"
          end

          distfile_names[filename] = true
          require_string(
            distfile["sha512"],
            "#{origin}.#{filename}.sha512",
            SHA512_PATTERN
          )
          urls = require_array(
            distfile["retrievalURLs"],
            "#{origin}.#{filename}.retrievalURLs"
          )
          if urls.empty?
            raise ValidationError, "#{origin}.#{filename} has no retrieval URL"
          end
          urls.each_with_index do |url, url_index|
            validate_url(
              url,
              "#{origin}.#{filename}.retrievalURLs[#{url_index}]",
              allow_file_urls
            )
          end
        end
      unless allow_file_urls
        expected_distfiles = EXPECTED_DISTFILES.fetch(origin) do
          raise ValidationError,
            "no pinned distfile inventory is defined for #{origin}"
        end
        unless distfile_names.keys.sort == expected_distfiles.sort
          raise ValidationError,
            "#{origin}.distfiles does not match the pinned v0.3.3 inventory"
        end
      end

      actual[origin] = {
        "aportsCommit" => commit,
        "binaryPackages" => packages,
        "declaredLicenseExpressions" => expressions
      }
    end

    unless actual == expected
      missing = expected.keys - actual.keys
      extra = actual.keys - expected.keys
      changed =
        (expected.keys & actual.keys).reject do |origin|
          expected[origin] == actual[origin]
        end
      raise ValidationError,
        "source acquisition manifest does not match generated inventory " \
        "(missing=#{missing.sort.inspect}, extra=#{extra.sort.inspect}, " \
        "changed=#{changed.sort.inspect})"
    end

    manifest_sources
  end

  def require_hash(value, label)
    raise ValidationError, "#{label} must be an object" unless value.is_a?(Hash)

    value
  end
  private_class_method :require_hash

  def require_array(value, label)
    raise ValidationError, "#{label} must be an array" unless value.is_a?(Array)

    value
  end
  private_class_method :require_array

  def require_string(value, label, pattern = nil)
    unless value.is_a?(String) && !value.empty?
      raise ValidationError, "#{label} must be a non-empty string"
    end
    if pattern && !value.match?(pattern)
      raise ValidationError, "#{label} has an invalid format"
    end

    value
  end
  private_class_method :require_string

  def safe_component(value, label)
    require_string(value, label, SAFE_COMPONENT_PATTERN)
  end
  private_class_method :safe_component

  def validate_url(value, label, allow_file_urls)
    text = require_string(value, label)
    uri = URI.parse(text)
    allowed_schemes = allow_file_urls ? %w[https file] : %w[https]
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
  private_class_method :validate_url

  def validate_archive_identity(document, label)
    archive = require_hash(document["archive"], "#{label}.archive")
    unless archive["version"] == ROOTFS_VERSION &&
      archive["sha256"] == ROOTFS_SHA256
      raise ValidationError,
        "#{label} does not identify the pinned RootFS archive"
    end
  end
  private_class_method :validate_archive_identity
end
