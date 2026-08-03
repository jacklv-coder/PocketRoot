#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "rubygems/package"
require "tempfile"

module PocketRootSourceRelease
  class VerificationError < StandardError; end

  RELEASE_VERSION = "0.2.0"
  MAX_ENTRIES = 20_000
  MAX_FILE_BYTES = 64 * 1024 * 1024
  MAX_ARCHIVE_CONTENT_BYTES = 256 * 1024 * 1024

  REQUIRED_PATHS = %w[
    Package.swift
    Package.resolved
    LICENSE
    NOTICE.md
    README.md
    README.en.md
    CHANGELOG.md
    CHANGELOG.en.md
  ].freeze

  FORBIDDEN_PATH_PATTERN = %r{
    (?:\A|/)[^/]+\.(?:
      app|ipa|xcarchive|xcframework|framework|dylib|so|a|o|
      zip|tar|tgz|gz|xz|bz2
    )\z
  }ix

  ALLOWED_SOURCE_EXTENSIONS = %w[
    .awk .c .h .json .md .mjs .plist .rb .resolved .sh .swift .template
    .tsv .txt .yml
  ].freeze
  ALLOWED_EXTENSIONLESS_FILES = %w[
    .gitignore .gitkeep LICENSE SHA256SUMS
  ].freeze
  ALLOWED_APPLICATION_MIME_TYPES = %w[
    application/javascript application/json application/x-empty application/xml
  ].freeze
  REVIEWED_ROOTFS_SOURCE_PATHS = %w[
    Compliance/RootFS
    Compliance/RootFS/v0.3.3
    Compliance/RootFS/v0.3.3/CORRESPONDING-SOURCE-REVIEW-RESULTS.json
    Compliance/RootFS/v0.3.3/EVIDENCE.json
    Compliance/RootFS/v0.3.3/LICENSE-INVENTORY.json
    Compliance/RootFS/v0.3.3/LICENSE-NOTICE-CANDIDATES.json
    Compliance/RootFS/v0.3.3/LICENSE-NOTICE-REVIEW-RESULTS.json
    Compliance/RootFS/v0.3.3/LICENSE-REVIEW-RESULTS.json
    Compliance/RootFS/v0.3.3/LICENSE-REVIEW.json
    Compliance/RootFS/v0.3.3/NOTICE.md
    Compliance/RootFS/v0.3.3/PACKAGE-INVENTORY.tsv
    Compliance/RootFS/v0.3.3/README.md
    Compliance/RootFS/v0.3.3/REBUILD-ENVIRONMENT-REVIEW.json
    Compliance/RootFS/v0.3.3/RUNTIME-CONFIGURATION.json
    Compliance/RootFS/v0.3.3/SBOM.spdx.json
    Compliance/RootFS/v0.3.3/SHA256SUMS
    Compliance/RootFS/v0.3.3/SOURCE-ACQUISITION.json
    Compliance/RootFS/v0.3.3/SOURCE-DELIVERY-INVENTORY.json
    Compliance/RootFS/v0.3.3/SOURCE-INVENTORY.json
    Sources/PocketRootCore/RootFS
    Sources/PocketRootCore/RootFS/RootFSManager.swift
    Sources/PocketRootCore/RootFS/RootFSMetadata.swift
    Sources/PocketRootCore/RootFS/RootFSProvider.swift
  ].freeze
  ROOTFS_PAYLOAD_COMPONENTS = %w[
    fakefs linux-rootfs root-filesystem rootfs
  ].freeze

  BINARY_MAGIC = {
    "ELF" => "\x7fELF".b,
    "ar archive" => "!<arch>\n".b,
    "gzip" => "\x1f\x8b\x08".b,
    "zip" => "PK\x03\x04".b,
    "xz" => "\xfd7zXZ\x00".b,
    "bzip2" => "BZh".b,
    "SQLite" => "SQLite format 3\x00".b,
    "Mach-O 32-bit big-endian" => "\xfe\xed\xfa\xce".b,
    "Mach-O 32-bit little-endian" => "\xce\xfa\xed\xfe".b,
    "Mach-O 64-bit big-endian" => "\xfe\xed\xfa\xcf".b,
    "Mach-O 64-bit little-endian" => "\xcf\xfa\xed\xfe".b,
    "Mach-O universal big-endian" => "\xca\xfe\xba\xbe".b,
    "Mach-O universal little-endian" => "\xbe\xba\xfe\xca".b,
    "Mach-O universal64 big-endian" => "\xca\xfe\xba\xbf".b,
    "Mach-O universal64 little-endian" => "\xbf\xba\xfe\xca".b
  }.freeze

  module_function

  def repository_root
    Pathname(__dir__).join("..").realpath
  end

  def validate_version(version)
    unless version.match?(/\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/)
      raise VerificationError, "version must be a plain SemVer value"
    end
    return if version == RELEASE_VERSION

    raise VerificationError,
      "this verifier is bound to source release #{RELEASE_VERSION}; " \
      "update release compliance before verifying #{version}"
  end

  def run_git(root, *arguments)
    output, error, status = Open3.capture3("git", *arguments, chdir: root.to_s)
    return output.strip if status.success?

    raise VerificationError,
      "git #{arguments.join(' ')} failed: #{error.strip}"
  end

  def verify_release_documents(root, version, require_released: true)
    changelog_suffix =
      require_released ? "\\d{4}-\\d{2}-\\d{2}" : "(?:Unreleased|\\d{4}-\\d{2}-\\d{2})"
    expected_headings = {
      "CHANGELOG.md" => /\A## #{Regexp.escape(version)} - #{changelog_suffix}\s*\z/,
      "CHANGELOG.en.md" => /\A## #{Regexp.escape(version)} - #{changelog_suffix}\s*\z/,
      "Docs/Releases/#{version}.md" => /\A# PocketRoot #{Regexp.escape(version)}\s*\z/,
      "Docs/en/Releases/#{version}.md" => /\A# PocketRoot #{Regexp.escape(version)}\s*\z/
    }

    expected_headings.each do |relative_path, heading|
      path = root.join(relative_path)
      raise VerificationError, "missing release document: #{relative_path}" unless path.file?
      unless path.each_line.any? { |line| line.match?(heading) }
        raise VerificationError,
          "#{relative_path} does not declare release #{version}"
      end
    end
  end

  def run_compliance(root, mode, tooling_root: root)
    script = tooling_root.join("Scripts/generate-release-compliance.rb")
    output, error, status = Open3.capture3(
      {"POCKETROOT_RELEASE_REPOSITORY_ROOT" => root.to_s},
      RbConfig.ruby,
      script.to_s,
      mode,
      chdir: root.to_s
    )
    return if status.success?

    raise VerificationError,
      "release compliance #{mode} failed: #{[output, error].join(' ').strip}"
  end

  def load_json(path, label)
    JSON.parse(path.binread)
  rescue Errno::ENOENT, JSON::ParserError => error
    raise VerificationError, "#{label} is invalid: #{error.message}"
  end

  def verify_source_readiness(
    root,
    version,
    tooling_root: root,
    require_ready: true
  )
    run_compliance(root, "--check", tooling_root: tooling_root)
    if require_ready
      run_compliance(root, "--require-source-ready", tooling_root: tooling_root)
    end

    readiness_path =
      root.join("Compliance/Release/experimental-v#{version}/READINESS.json")
    decisions_path = root.join("Compliance/Release/RELEASE-DECISIONS.json")
    readiness = load_json(readiness_path, "release readiness")
    decisions = load_json(decisions_path, "release decisions")
    source_status = readiness.dig("tracks", "sourcePackageRelease", "status")
    unless readiness["releaseVersion"] == version &&
      decisions["releaseVersion"] == version &&
      %w[blocked ready].include?(source_status)
      raise VerificationError,
        "source readiness is not bound to release #{version}"
    end
    if require_ready &&
      (
        source_status != "ready" ||
        !%w[
          source-release-authorized
          source-and-runtime-distribution-authorized
        ].include?(decisions["status"])
      )
      raise VerificationError,
        "source authorization is not bound to release #{version}"
    end
    source_status
  end

  def verify_annotated_tag(root, ref, tag)
    unless tag.match?(/\Av(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/)
      raise VerificationError, "release tag must use vMAJOR.MINOR.PATCH"
    end

    object_type = run_git(root, "cat-file", "-t", tag)
    raise VerificationError, "#{tag} must be an annotated tag" unless object_type == "tag"

    tagged_commit = run_git(root, "rev-parse", "#{tag}^{commit}")
    release_commit = run_git(root, "rev-parse", "#{ref}^{commit}")
    return if tagged_commit == release_commit

    raise VerificationError,
      "#{tag} points to #{tagged_commit}, not release ref #{release_commit}"
  end

  def create_archive(root, ref, version, archive_path)
    tracked_paths = run_git(
      root,
      "ls-tree", "-r", "--name-only", "-z", "#{ref}^{tree}"
    ).split("\0")
    attributes_path = tracked_paths.find do |path|
      File.basename(path) == ".gitattributes"
    end
    if attributes_path
      raise VerificationError,
        "source release ref contains #{attributes_path}; " \
        "Git archive export filtering is not allowed"
    end

    prefix = "PocketRoot-#{version}/"
    success = system(
      "git",
      "archive",
      "--format=tar",
      "--prefix=#{prefix}",
      "--output=#{archive_path}",
      ref,
      chdir: root.to_s
    )
    raise VerificationError, "git archive failed for #{ref}" unless success

    prefix
  end

  def relative_entry_path(path, prefix, directory:)
    unless path.start_with?(prefix)
      raise VerificationError, "archive path is outside #{prefix}: #{path}"
    end
    relative = path.delete_prefix(prefix)
    relative = relative.delete_suffix("/") if directory
    return "" if directory && relative.empty?

    components = relative.split("/", -1)
    if relative.empty? || relative.start_with?("/") ||
      components.any? { |component| component.empty? || %w[. ..].include?(component) } ||
      relative.include?("\0")
      raise VerificationError, "unsafe source archive path: #{path}"
    end
    relative
  end

  def global_pax_metadata_entry?(entry)
    path = entry.full_name.delete_suffix("/")
    path == "pax_global_header" && entry.header.typeflag == "g"
  end

  def local_pax_helper_entry?(entry)
    path = entry.full_name.delete_suffix("/")
    path.match?(/\A[0-9a-f]{40,64}\.(?:paxheader|data)\z/) &&
      ["x", "0", "5"].include?(entry.header.typeflag)
  end

  def reject_local_pax_helper!(entry)
    return unless local_pax_helper_entry?(entry)

    raise VerificationError,
      "local PAX extended paths are not allowed in a source release: " \
      "#{entry.full_name}"
  end

  def rootfs_payload_path?(relative)
    components = relative.downcase.split("/")
    filesystem_path = components.join("/")
    return true if filesystem_path.match?(
      %r{(?:\A|/)(?:
        etc/(?:passwd|group|shadow|os-release)(?:\.txt)?|
        lib/apk/db/installed(?:\.txt)?|
        var/lib/apk/(?:installed|world)(?:\.txt)?
      )\z}x
    )

    return false if (components & ROOTFS_PAYLOAD_COMPONENTS).empty?

    !REVIEWED_ROOTFS_SOURCE_PATHS.include?(relative)
  end

  def audit_archive(archive_path, prefix, required_paths: REQUIRED_PATHS)
    seen = {}
    regular_files = []
    total_bytes = 0

    File.open(archive_path, "rb") do |archive|
      Gem::Package::TarReader.new(archive) do |tar|
        tar.each do |entry|
          path = entry.full_name
          # Git's global commit metadata is inert. Local PAX helpers are
          # rejected because older TarReader versions can expose only their
          # hash-named storage entries and hide the logical long-path file.
          next if global_pax_metadata_entry?(entry)
          reject_local_pax_helper!(entry)
          relative = relative_entry_path(
            path,
            prefix,
            directory: entry.directory?
          )
          if !relative.empty? && rootfs_payload_path?(relative)
            raise VerificationError, "forbidden RootFS payload path: #{path}"
          end
          raise VerificationError, "duplicate archive path: #{path}" if seen.key?(path)
          seen[path] = true
          raise VerificationError, "source archive exceeds #{MAX_ENTRIES} entries" if seen.length > MAX_ENTRIES
          audit_path = path.delete_suffix("/")
          if audit_path.match?(FORBIDDEN_PATH_PATTERN)
            raise VerificationError, "forbidden source-release path: #{path}"
          end

          next if entry.directory?
          raise VerificationError, "non-regular archive entry: #{path}" unless entry.file?
          raise VerificationError, "oversized source file: #{path}" if entry.size > MAX_FILE_BYTES

          total_bytes += entry.size
          if total_bytes > MAX_ARCHIVE_CONTENT_BYTES
            raise VerificationError, "source archive content exceeds byte limit"
          end

          contents = entry.read
          header = contents.byteslice(0, [contents.bytesize, 512].min)
          BINARY_MAGIC.each do |kind, magic|
            next unless header.start_with?(magic)

            raise VerificationError, "forbidden #{kind} payload: #{path}"
          end
          if header.bytesize >= 262 && header.byteslice(257, 5) == "ustar"
            raise VerificationError, "forbidden tar payload: #{path}"
          end
          text = contents.dup.force_encoding(Encoding::UTF_8)
          unless text.valid_encoding? && !contents.include?("\0")
            raise VerificationError, "unknown binary payload: #{path}"
          end
          unless contents.bytes.all? { |byte| [9, 10, 13, 32].include?(byte) }
            mime, error, status = Open3.capture3(
              {"LC_ALL" => "C"},
              "file", "--brief", "--mime-type", "-",
              stdin_data: contents
            )
            unless status.success?
              raise VerificationError,
                "file-type detection failed for #{path}: #{error.strip}"
            end
            mime = mime.strip
            unless mime.start_with?("text/") ||
              ALLOWED_APPLICATION_MIME_TYPES.include?(mime)
              raise VerificationError,
                "unsupported MIME type #{mime.inspect}: #{path}"
            end
          end
          basename = File.basename(relative)
          extension = File.extname(basename).downcase
          unless ALLOWED_SOURCE_EXTENSIONS.include?(extension) ||
            (extension.empty? && ALLOWED_EXTENSIONLESS_FILES.include?(basename))
            raise VerificationError, "unsupported source-release file type: #{path}"
          end
          regular_files << relative
        end
      end
    end

    missing = required_paths - regular_files
    unless missing.empty?
      raise VerificationError,
        "source archive is missing required files: #{missing.join(', ')}"
    end

    {
      "entryCount" => seen.length,
      "regularFileCount" => regular_files.length,
      "uncompressedFileBytes" => total_bytes,
      "archiveSha256" => Digest::SHA256.file(archive_path).hexdigest,
      "rootFSIncluded" => false,
      "runtimeArtifactIncluded" => false
    }
  end

  def materialize_archive(archive_path, prefix, destination)
    release_root = destination.join(prefix.delete_suffix("/"))
    release_root.mkpath
    File.open(archive_path, "rb") do |archive|
      Gem::Package::TarReader.new(archive) do |tar|
        tar.each do |entry|
          path = entry.full_name
          next if global_pax_metadata_entry?(entry)
          reject_local_pax_helper!(entry)
          relative = relative_entry_path(
            path,
            prefix,
            directory: entry.directory?
          )
          next if relative.empty?

          target = release_root.join(relative)
          if entry.directory?
            target.mkpath
          else
            target.dirname.mkpath
            target.binwrite(entry.read)
          end
        end
      end
    end
    release_root
  end

  def verify(
    root:,
    ref:,
    version:,
    required_tag: nil,
    output: nil,
    tooling_root: root,
    require_source_ready: true
  )
    validate_version(version)
    if required_tag
      unless require_source_ready
        raise VerificationError,
          "tag verification cannot allow a blocked source track"
      end
      expected_tag = "v#{version}"
      unless required_tag == expected_tag
        raise VerificationError,
          "tag #{required_tag} does not match version #{version}"
      end
      verify_annotated_tag(root, ref, required_tag)
    end

    archive = output ? Pathname(output).expand_path : nil
    temporary = nil
    unless archive
      temporary = Tempfile.new(["pocketroot-source-release-", ".tar"])
      temporary.close
      archive = Pathname(temporary.path)
    end
    FileUtils.mkdir_p(archive.dirname)

    prefix = create_archive(root, ref, version, archive)
    release_paths = [
      "Docs/Releases/#{version}.md",
      "Docs/en/Releases/#{version}.md"
    ]
    result = audit_archive(
      archive,
      prefix,
      required_paths: REQUIRED_PATHS + release_paths
    )
    source_status = nil
    Dir.mktmpdir("pocketroot-source-release-snapshot-") do |directory|
      release_root = materialize_archive(
        archive,
        prefix,
        Pathname(directory)
      )
      verify_release_documents(
        release_root,
        version,
        require_released: require_source_ready
      )
      source_status = verify_source_readiness(
        release_root,
        version,
        tooling_root: Pathname(tooling_root).realpath,
        require_ready: require_source_ready
      )
    end
    result = result.merge(
      "releaseVersion" => version,
      "ref" => ref,
      "commit" => run_git(root, "rev-parse", "#{ref}^{commit}"),
      "sourceTrack" => source_status
    )
    result["archivePath"] = archive.to_s if output
    result
  ensure
    temporary&.unlink
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options = {
      ref: "HEAD",
      root: PocketRootSourceRelease.repository_root,
      require_source_ready: true
    }
    parser = OptionParser.new do |cli|
      cli.banner = "Usage: verify-source-release.rb --version VERSION [options]"
      cli.on("--version VERSION", "Plain SemVer release version") do |value|
        options[:version] = value
      end
      cli.on("--ref REF", "Git ref to archive (default: HEAD)") do |value|
        options[:ref] = value
      end
      cli.on("--root PATH", "Repository containing the candidate ref") do |value|
        options[:root] = Pathname(value).expand_path
      end
      cli.on("--tooling-root PATH", "Trusted release-verifier checkout") do |value|
        options[:tooling_root] = Pathname(value).expand_path
      end
      cli.on("--require-tag TAG", "Require an annotated tag at REF") do |value|
        options[:required_tag] = value
      end
      cli.on(
        "--allow-source-blocked",
        "Audit an untagged release candidate without granting source-release authorization"
      ) do
        options[:require_source_ready] = false
      end
      cli.on("--output PATH", "Keep the verified tar at PATH") do |value|
        options[:output] = value
      end
    end
    parser.parse!
    raise OptionParser::MissingArgument, "--version" unless options[:version]

    result = PocketRootSourceRelease.verify(
      root: Pathname(options[:root]),
      ref: options[:ref],
      version: options[:version],
      required_tag: options[:required_tag],
      output: options[:output],
      tooling_root: options.fetch(:tooling_root, options[:root]),
      require_source_ready: options[:require_source_ready]
    )
    puts JSON.pretty_generate(result)
  rescue OptionParser::ParseError,
         PocketRootSourceRelease::VerificationError => error
    warn "Source release verification failed: #{error.message}"
    exit 2
  end
end
