#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "rubygems/package"
require "uri"
require "zlib"
require_relative "rootfs-license-review"
require_relative "rootfs-license-review-results"
require_relative "rootfs-source-acquisition"

ARCHIVE_VERSION = "v0.3.3"
ARCHIVE_URL =
  "https://github.com/Lolendor/ish-arm64-pkg/releases/download/v0.3.3/fs.tar.gz"
ARCHIVE_BYTE_COUNT = 6_581_376
ARCHIVE_SHA256 =
  "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
GENERATED_AT = "2026-07-26T00:00:00Z"
GUEST_ROOT = "fs/data/srv/vms/.template"
APORTS_REPOSITORY = "main"

REQUIRED_MEMBERS = {
  installed_database: "#{GUEST_ROOT}/lib/apk/db/installed",
  repositories: "#{GUEST_ROOT}/etc/apk/repositories",
  resolver: "#{GUEST_ROOT}/etc/resolv.conf",
  world: "#{GUEST_ROOT}/etc/apk/world",
  architecture: "#{GUEST_ROOT}/etc/apk/arch",
  os_release: "#{GUEST_ROOT}/etc/os-release"
}.freeze

class ComplianceError < StandardError
end

def parse_options
  options = {
    output: "Compliance/RootFS/v0.3.3",
    source_acquisition:
      "Compliance/RootFS/v0.3.3/SOURCE-ACQUISITION.json",
    license_review:
      "Compliance/RootFS/v0.3.3/LICENSE-REVIEW.json",
    license_review_results:
      "Compliance/RootFS/v0.3.3/LICENSE-REVIEW-RESULTS.json",
    check: false
  }

  parser = OptionParser.new do |commands|
    commands.banner =
      "Usage: ruby Scripts/generate-rootfs-compliance.rb --archive PATH [options]"
    commands.on("--archive PATH", "Pinned RootFS archive to inspect") do |path|
      options[:archive] = path
    end
    commands.on("--output DIR", "Evidence directory (default: #{options[:output]})") do |path|
      options[:output] = path
    end
    commands.on(
      "--source-acquisition PATH",
      "Pinned source-acquisition manifest"
    ) do |path|
      options[:source_acquisition] = path
    end
    commands.on(
      "--license-review PATH",
      "Pinned license-review candidate manifest"
    ) do |path|
      options[:license_review] = path
    end
    commands.on(
      "--license-review-results PATH",
      "Pinned engineering review results"
    ) do |path|
      options[:license_review_results] = path
    end
    commands.on("--check", "Compare generated evidence without writing files") do
      options[:check] = true
    end
  end

  parser.parse!
  raise OptionParser::MissingArgument, "--archive" unless options[:archive]
  raise OptionParser::InvalidOption, ARGV.join(" ") unless ARGV.empty?

  options
end

def load_json_document(path, label)
  document_path = Pathname(path)
  unless document_path.file?
    raise ComplianceError, "#{label} is not a regular file: #{path}"
  end

  contents = document_path.binread
  {
    contents: contents,
    document: JSON.parse(contents)
  }
rescue JSON::ParserError => error
  raise ComplianceError, "#{label} is invalid JSON: #{error.message}"
end

def verify_archive(path)
  archive = Pathname(path)
  raise ComplianceError, "RootFS archive is not a regular file: #{path}" unless archive.file?

  actual_size = archive.size
  unless actual_size == ARCHIVE_BYTE_COUNT
    raise ComplianceError,
      "RootFS archive size mismatch: expected #{ARCHIVE_BYTE_COUNT}, got #{actual_size}"
  end

  actual_sha256 = Digest::SHA256.file(archive).hexdigest
  unless actual_sha256 == ARCHIVE_SHA256
    raise ComplianceError,
      "RootFS archive SHA-256 mismatch: expected #{ARCHIVE_SHA256}, got #{actual_sha256}"
  end

  archive
end

def verify_source_acquisition(path)
  loaded = load_json_document(path, "Source-acquisition manifest")
  contents = loaded.fetch(:contents)
  manifest = loaded.fetch(:document)
  archive = manifest["archive"]
  unless manifest["schemaVersion"] == 1 &&
    archive.is_a?(Hash) &&
    archive["version"] == ARCHIVE_VERSION &&
    archive["sha256"] == ARCHIVE_SHA256 &&
    manifest["bundleStatus"] == "external-materialization-required" &&
    manifest["redistributionApproved"] == false
    raise ComplianceError,
      "Source-acquisition manifest does not preserve the pinned archive and release gates"
  end

  {
    contents: contents,
    document: manifest
  }
end

def license_or_notice_path?(name)
  downcased = name.downcase
  basename = File.basename(downcased)

  downcased.include?("/licenses/") ||
    basename.match?(/\A(?:license|copying|notice)(?:[._-].*)?\z/)
end

def inspect_archive(archive)
  required_by_path = REQUIRED_MEMBERS.invert
  captured = {}
  archive_paths = {}
  license_notice_paths = []

  Zlib::GzipReader.open(archive.to_s) do |gzip|
    Gem::Package::TarReader.new(gzip) do |tar|
      tar.each do |entry|
        name = entry.full_name
        raise ComplianceError, "Duplicate tar member: #{name}" if archive_paths.key?(name)

        archive_paths[name] = true
        if entry.file? && license_or_notice_path?(name)
          license_notice_paths << name.delete_prefix("#{GUEST_ROOT}/")
        end

        key = required_by_path[name]
        next unless key

        raise ComplianceError, "Duplicate required tar member: #{name}" if captured.key?(key)
        raise ComplianceError, "Required tar member is not a file: #{name}" unless entry.file?
        raise ComplianceError, "Required tar member is unexpectedly large: #{name}" if entry.size > 2_097_152

        captured[key] = entry.read
      end
    end
  end

  missing = REQUIRED_MEMBERS.keys - captured.keys
  unless missing.empty?
    paths = missing.map { |key| REQUIRED_MEMBERS.fetch(key) }
    raise ComplianceError, "Missing required tar members: #{paths.join(", ")}"
  end

  {
    content: captured,
    archive_paths: archive_paths,
    license_notice_paths: license_notice_paths.sort
  }
end

def parse_installed_database(contents)
  packages = contents.split(/\n{2,}/).map do |record|
    fields = {}
    record.each_line do |line|
      match = line.chomp.match(/\A([A-Za-z]):(.*)\z/)
      next unless match
      next if fields.key?(match[1])

      fields[match[1]] = match[2]
    end
    next unless fields["P"]

    required = %w[P V A L o c]
    missing = required.reject { |field| fields[field] && !fields[field].empty? }
    unless missing.empty?
      raise ComplianceError,
        "Package #{fields["P"].inspect} is missing fields: #{missing.join(", ")}"
    end

    {
      name: fields.fetch("P"),
      version: fields.fetch("V"),
      architecture: fields.fetch("A"),
      license: fields.fetch("L"),
      source_origin: fields.fetch("o"),
      source_commit: fields.fetch("c"),
      upstream_url: fields["U"] || "NOASSERTION",
      description: fields["T"] || "",
      maintainer: fields["m"] || "NOASSERTION",
      installed_size: Integer(fields["I"] || "0", 10),
      package_size: Integer(fields["S"] || "0", 10)
    }
  end.compact

  raise ComplianceError, "Installed package database is empty" if packages.empty?

  duplicate_names = packages.group_by { |package| package[:name] }
    .select { |_name, entries| entries.length > 1 }
    .keys
  unless duplicate_names.empty?
    raise ComplianceError, "Duplicate installed packages: #{duplicate_names.sort.join(", ")}"
  end

  packages.sort_by { |package| package[:name] }
end

def non_comment_lines(contents)
  contents.lines
    .map(&:strip)
    .reject { |line| line.empty? || line.start_with?("#") }
end

def parse_os_release(contents)
  contents.lines.each_with_object({}) do |line, values|
    match = line.chomp.match(/\A([A-Z0-9_]+)=(.*)\z/)
    next unless match

    value = match[2]
    if value.start_with?("\"") && value.end_with?("\"")
      value = value[1...-1].gsub("\\\"", "\"").gsub("\\\\", "\\")
    end
    values[match[1]] = value
  end.sort.to_h
end

def spdx_id(package_name)
  "SPDXRef-Package-#{package_name.gsub(/[^A-Za-z0-9.-]/, "-")}"
end

def purl(package)
  name = URI::DEFAULT_PARSER.escape(package[:name])
  version = URI::DEFAULT_PARSER.escape(package[:version])
  "pkg:apk/alpine/#{name}@#{version}?arch=#{package[:architecture]}&distro=alpine-3.19.1"
end

def source_recipe_url(source)
  "https://gitlab.alpinelinux.org/alpine/aports/-/raw/" \
    "#{source.fetch(:commit)}/#{APORTS_REPOSITORY}/#{source.fetch(:origin)}/APKBUILD"
end

def source_tree_url(source)
  "https://gitlab.alpinelinux.org/alpine/aports/-/tree/" \
    "#{source.fetch(:commit)}/#{APORTS_REPOSITORY}/#{source.fetch(:origin)}"
end

def copyleft_license?(expression)
  expression.match?(/\b(?:A?GPL|LGPL|MPL|EPL|CDDL)-/)
end

def source_inventory(packages)
  groups = packages.group_by do |package|
    [package[:source_origin], package[:source_commit]]
  end

  groups.map do |(origin, commit), binaries|
    source = { origin: origin, commit: commit }
    {
      "sourceOrigin" => origin,
      "aportsCommit" => commit,
      "aportsRepository" => APORTS_REPOSITORY,
      "buildRecipeURL" => source_recipe_url(source),
      "buildRecipeTreeURL" => source_tree_url(source),
      "binaryPackages" => binaries.map { |package| package[:name] }.sort,
      "binaryVersions" => binaries.map { |package| package[:version] }.uniq.sort,
      "declaredLicenseExpressions" =>
        binaries.map { |package| package[:license] }.uniq.sort,
      "containsDeclaredCopyleft" =>
        binaries.any? { |package| copyleft_license?(package[:license]) },
      "correspondingSourceStatus" =>
        "verified-acquisition-recorded-external-bundle-required"
    }
  end.sort_by { |source| source.fetch("sourceOrigin") }
end

def pretty_json(value)
  "#{JSON.pretty_generate(value)}\n"
end

def package_inventory_tsv(packages)
  headings = [
    "package",
    "version",
    "architecture",
    "declared_license",
    "source_origin",
    "aports_commit",
    "upstream_url",
    "installed_size_bytes",
    "package_size_bytes",
    "maintainer"
  ]

  rows = packages.map do |package|
    [
      package[:name],
      package[:version],
      package[:architecture],
      package[:license],
      package[:source_origin],
      package[:source_commit],
      package[:upstream_url],
      package[:installed_size],
      package[:package_size],
      package[:maintainer]
    ].map do |value|
      text = value.to_s
      raise ComplianceError, "Tab or newline in package inventory value" if text.match?(/[\t\r\n]/)

      text
    end.join("\t")
  end

  "#{([headings.join("\t")] + rows).join("\n")}\n"
end

def sbom(packages)
  package_entries = packages.map do |package|
    {
      "SPDXID" => spdx_id(package[:name]),
      "name" => package[:name],
      "versionInfo" => package[:version],
      "supplier" => "Organization: Alpine Linux",
      "downloadLocation" => "NOASSERTION",
      "filesAnalyzed" => false,
      "licenseConcluded" => "NOASSERTION",
      "licenseDeclared" => package[:license],
      "copyrightText" => "NOASSERTION",
      "summary" => package[:description],
      "homepage" => package[:upstream_url],
      "sourceInfo" =>
        "Alpine source origin #{package[:source_origin]} at aports commit " \
        "#{package[:source_commit]}",
      "externalRefs" => [
        {
          "referenceCategory" => "PACKAGE-MANAGER",
          "referenceType" => "purl",
          "referenceLocator" => purl(package)
        }
      ]
    }
  end

  {
    "spdxVersion" => "SPDX-2.3",
    "dataLicense" => "CC0-1.0",
    "SPDXID" => "SPDXRef-DOCUMENT",
    "name" => "PocketRoot pinned Alpine RootFS #{ARCHIVE_VERSION}",
    "documentNamespace" =>
      "https://github.com/jacklv-coder/PocketRoot/sbom/rootfs/" \
      "#{ARCHIVE_VERSION}/#{ARCHIVE_SHA256}",
    "creationInfo" => {
      "created" => GENERATED_AT,
      "creators" => [
        "Tool: PocketRoot Scripts/generate-rootfs-compliance.rb"
      ]
    },
    "documentDescribes" => package_entries.map { |package| package.fetch("SPDXID") },
    "packages" => package_entries,
    "relationships" => package_entries.map do |package|
      {
        "spdxElementId" => "SPDXRef-DOCUMENT",
        "relationshipType" => "DESCRIBES",
        "relatedSpdxElement" => package.fetch("SPDXID")
      }
    end
  }
end

def runtime_configuration(content, archive_paths, os_release)
  apk_paths = [
    "#{GUEST_ROOT}/sbin/apk",
    "#{GUEST_ROOT}/usr/sbin/apk"
  ].select { |path| archive_paths.key?(path) }

  {
    "schemaVersion" => 1,
    "archive" => {
      "version" => ARCHIVE_VERSION,
      "sha256" => ARCHIVE_SHA256
    },
    "guest" => {
      "id" => os_release["ID"],
      "versionID" => os_release["VERSION_ID"],
      "architecture" => non_comment_lines(content.fetch(:architecture)).first
    },
    "apk" => {
      "installed" => !apk_paths.empty?,
      "paths" => apk_paths.map { |path| path.delete_prefix("#{GUEST_ROOT}/") },
      "repositories" => non_comment_lines(content.fetch(:repositories)),
      "world" => non_comment_lines(content.fetch(:world))
    },
    "resolverConfiguration" => non_comment_lines(content.fetch(:resolver)),
    "review" => {
      "status" => "recorded-requires-product-policy",
      "observations" => [
        "The package manager remains installed.",
        "The configured repositories allow retrieval from Alpine main and community.",
        "The resolver contains fixed public DNS server addresses.",
        "No product decision to retain, restrict, proxy, or disable these capabilities is recorded."
      ]
    }
  }
end

def license_inventory(
  packages,
  license_notice_paths,
  license_review_entries,
  license_review_result_entries
)
  expressions = Hash.new(0)
  packages.each { |package| expressions[package[:license]] += 1 }
  identifiers = expressions.keys.flat_map do |expression|
    expression.scan(/[A-Za-z0-9][A-Za-z0-9.+-]*/)
  end.reject { |token| %w[AND OR WITH].include?(token) }.uniq.sort

  {
    "schemaVersion" => 1,
    "archive" => {
      "version" => ARCHIVE_VERSION,
      "sha256" => ARCHIVE_SHA256
    },
    "declaredLicenseExpressions" => expressions.sort.to_h,
    "declaredLicenseIdentifiers" => identifiers,
    "licenseOrNoticeFilesFoundInGuestTemplate" => license_notice_paths,
    "indexedExternalReviewCandidates" =>
      license_review_entries.sum do |entry|
        entry.fetch("candidateEvidence").length
      end,
    "engineeringReviewedCandidates" =>
      license_review_result_entries.sum do |entry|
        entry.fetch("candidateResults").length
      end,
    "sourceOriginsWithOpenReviewItems" =>
      license_review_result_entries.count do |entry|
        !entry.fetch("remainingReviewItems").empty?
      end,
    "engineeringReviewCompleted" => true,
    "completeLicenseTextBundlePresent" => false,
    "completePackageNoticeSetPresent" => false,
    "legalReviewApproved" => false,
    "status" => "engineering-reviewed-open-release-gates"
  }
end

def notice_markdown(
  packages,
  source_entries,
  license_notice_paths,
  license_review_entries,
  license_review_result_entries
)
  package_rows = packages.map do |package|
    "| `#{package[:name]}` | `#{package[:version]}` | " \
      "`#{package[:license]}` | `#{package[:source_origin]}` | " \
      "`#{package[:source_commit]}` |"
  end

  copyleft_sources = source_entries
    .select { |source| source.fetch("containsDeclaredCopyleft") }
    .map { |source| "`#{source.fetch("sourceOrigin")}`" }

  found_text =
    if license_notice_paths.empty?
      "No file whose path identifies it as LICENSE, COPYING, NOTICE, or a " \
        "license-directory member was found in the guest template."
    else
      "The archive contains these candidate files: " \
        "#{license_notice_paths.map { |path| "`#{path}`" }.join(", ")}."
    end
  candidate_count = license_review_entries.sum do |entry|
    entry.fetch("candidateEvidence").length
  end
  remaining_origins = license_review_result_entries.select do |entry|
    !entry.fetch("remainingReviewItems").empty?
  end
  resolved_origins = license_review_result_entries.reject do |entry|
    !entry.fetch("remainingReviewItems").empty?
  end

  <<~MARKDOWN
    # Pinned RootFS attribution inventory

    Generated from the exact `#{ARCHIVE_VERSION}` archive with SHA-256
    `#{ARCHIVE_SHA256}`.

    > This is reproducible engineering evidence, not a complete legal NOTICE,
    > license bundle, corresponding-source offer, or redistribution approval.
    > Engineering candidate review is complete. Package-specific open items,
    > legal review, and redistribution approval remain required.

    ## Installed packages

    | Package | Version | Declared license | Source origin | aports commit |
    | --- | --- | --- | --- | --- |
    #{package_rows.join("\n")}

    ## License and notice status

    #{found_text}

    Declared identifiers and expressions are recorded in
    `LICENSE-INVENTORY.json`. `LICENSE-REVIEW.json` pins #{candidate_count}
    candidate license, attribution, declaration, and inline-notice files across
    all #{license_review_entries.length} source origins. The external review tool
    extracts and verifies those candidates from the pinned source-review bundle.
    `LICENSE-REVIEW-RESULTS.json` records the checksum-bound engineering review
    of all #{candidate_count} candidates. All indexed review items are resolved
    for #{resolved_origins.map { |entry| "`#{entry.fetch("sourceOrigin")}`" }.join(", ")}.
    #{remaining_origins.length} source origins still have package-specific open
    items, so this is not a complete or legally approved license/NOTICE bundle.

    ## Corresponding-source status

    Exact Alpine aports recipe locators are recorded for all
    #{source_entries.length} source origins in `SOURCE-INVENTORY.json`.
    `SOURCE-ACQUISITION.json` pins each aports snapshot and upstream distfile
    with cryptographic checksums. The repository script can materialize those
    inputs into a new external review directory.
    Source origins with declared copyleft terms are
    #{copyleft_sources.join(", ")}.

    No source archive is committed or shipped by this repository. A materialized
    directory still requires package-specific license/NOTICE, modification,
    build-completeness, offer-mechanics, and legal review before it can be
    treated as corresponding-source delivery material.

    ## Runtime configuration status

    `RUNTIME-CONFIGURATION.json` records the package manager, repositories, DNS
    resolver values, architecture, and world set. Product policy for retaining,
    restricting, proxying, or disabling package installation and networking
    remains open.
  MARKDOWN
end

def evidence(
  packages,
  source_entries,
  inspected,
  license_review_entries,
  license_review_result_entries
)
  {
    "schemaVersion" => 1,
    "generatedAt" => GENERATED_AT,
    "generator" => "Scripts/generate-rootfs-compliance.rb",
    "archive" => {
      "version" => ARCHIVE_VERSION,
      "url" => ARCHIVE_URL,
      "byteCount" => ARCHIVE_BYTE_COUNT,
      "sha256" => ARCHIVE_SHA256
    },
    "inputMembers" => REQUIRED_MEMBERS.transform_values do |path|
      {
        "path" => path,
        "sha256" => Digest::SHA256.hexdigest(
          inspected.fetch(:content).fetch(REQUIRED_MEMBERS.key(path))
        )
      }
    end,
    "counts" => {
      "installedBinaryPackages" => packages.length,
      "sourceOrigins" => source_entries.length,
      "declaredLicenseExpressions" =>
        packages.map { |package| package[:license] }.uniq.length,
      "licenseOrNoticeFilesInGuestTemplate" =>
        inspected.fetch(:license_notice_paths).length,
      "indexedExternalLicenseReviewCandidates" =>
        license_review_entries.sum do |entry|
          entry.fetch("candidateEvidence").length
        end,
      "engineeringReviewedLicenseCandidates" =>
        license_review_result_entries.sum do |entry|
          entry.fetch("candidateResults").length
        end,
      "sourceOriginsWithRemainingLicenseReviewItems" =>
        license_review_result_entries.count do |entry|
          !entry.fetch("remainingReviewItems").empty?
        end
    },
    "engineeringStatus" => {
      "completeInstalledPackageInventory" => true,
      "machineReadableSPDXSBOM" => true,
      "runtimeConfigurationRecorded" => true,
      "completeSourceAcquisitionManifest" => true,
      "completeLicenseReviewCandidateIndex" => true,
      "licenseCandidateEngineeringReviewCompleted" => true,
      "completeLicenseAndNoticeBundle" => false,
      "correspondingSourceBundleCollected" => false,
      "redistributionApproved" => false
    }
  }
end

def build_outputs(
  archive,
  source_acquisition,
  license_review,
  license_review_results
)
  inspected = inspect_archive(archive)
  content = inspected.fetch(:content)
  packages = parse_installed_database(content.fetch(:installed_database))
  os_release = parse_os_release(content.fetch(:os_release))

  unless packages.all? { |package| package[:architecture] == "aarch64" }
    raise ComplianceError, "Installed package inventory contains a non-aarch64 package"
  end
  unless os_release["ID"] == "alpine" && os_release["VERSION_ID"] == "3.19.1"
    raise ComplianceError, "Unexpected guest OS release: #{os_release.inspect}"
  end

  source_entries = source_inventory(packages)
  generated_source_inventory = {
    "archive" => {
      "version" => ARCHIVE_VERSION,
      "sha256" => ARCHIVE_SHA256
    },
    "sourceOrigins" => source_entries
  }
  begin
    RootFSSourceAcquisition.validate_manifest(
      source_acquisition.fetch(:document),
      generated_source_inventory
    )
  rescue RootFSSourceAcquisition::ValidationError => error
    raise ComplianceError,
      "Invalid source-acquisition manifest: #{error.message}"
  end
  begin
    license_review_entries = RootFSLicenseReview.validate_manifest(
      license_review.fetch(:document),
      source_acquisition.fetch(:document),
      generated_source_inventory,
      source_acquisition_bytes: source_acquisition.fetch(:contents)
    )
  rescue RootFSLicenseReview::ValidationError => error
    raise ComplianceError,
      "Invalid license-review manifest: #{error.message}"
  end
  begin
    license_review_result_entries =
      RootFSLicenseReviewResults.validate_manifest(
        license_review_results.fetch(:document),
        license_review.fetch(:document),
        license_review_bytes: license_review.fetch(:contents)
      )
  rescue RootFSLicenseReviewResults::ValidationError => error
    raise ComplianceError,
      "Invalid license-review results: #{error.message}"
  end
  outputs = {
    "EVIDENCE.json" => pretty_json(
      evidence(
        packages,
        source_entries,
        inspected,
        license_review_entries,
        license_review_result_entries
      )
    ),
    "LICENSE-INVENTORY.json" => pretty_json(
      license_inventory(
        packages,
        inspected.fetch(:license_notice_paths),
        license_review_entries,
        license_review_result_entries
      )
    ),
    "LICENSE-REVIEW.json" => license_review.fetch(:contents),
    "LICENSE-REVIEW-RESULTS.json" =>
      license_review_results.fetch(:contents),
    "NOTICE.md" => notice_markdown(
      packages,
      source_entries,
      inspected.fetch(:license_notice_paths),
      license_review_entries,
      license_review_result_entries
    ),
    "PACKAGE-INVENTORY.tsv" => package_inventory_tsv(packages),
    "RUNTIME-CONFIGURATION.json" => pretty_json(
      runtime_configuration(content, inspected.fetch(:archive_paths), os_release)
    ),
    "SBOM.spdx.json" => pretty_json(sbom(packages)),
    "SOURCE-ACQUISITION.json" => source_acquisition.fetch(:contents),
    "SOURCE-INVENTORY.json" => pretty_json(
      {
        "schemaVersion" => 1,
        "archive" => {
          "version" => ARCHIVE_VERSION,
          "sha256" => ARCHIVE_SHA256
        },
        "sourceOrigins" => source_entries,
        "completeCorrespondingSourceBundlePresent" => false,
        "status" => "verified-acquisition-recorded-external-bundle-required"
      }
    )
  }

  checksum_lines = outputs.sort.map do |filename, contents|
    "#{Digest::SHA256.hexdigest(contents)}  #{filename}"
  end
  outputs["SHA256SUMS"] = "#{checksum_lines.join("\n")}\n"
  outputs
end

def check_outputs(output_directory, expected)
  failures = []
  expected.each do |filename, contents|
    path = output_directory.join(filename)
    if !path.file?
      failures << "missing #{path}"
    elsif path.binread != contents
      failures << "out of date #{path}"
    end
  end

  unless failures.empty?
    raise ComplianceError,
      "RootFS compliance evidence is not reproducible:\n- #{failures.join("\n- ")}"
  end
end

def write_outputs(output_directory, expected)
  FileUtils.mkdir_p(output_directory)
  expected.each do |filename, contents|
    output_directory.join(filename).binwrite(contents)
  end
end

begin
  options = parse_options
  archive = verify_archive(options.fetch(:archive))
  license_review = load_json_document(
    options.fetch(:license_review),
    "License-review manifest"
  )
  license_review_results = load_json_document(
    options.fetch(:license_review_results),
    "License-review results"
  )
  source_acquisition =
    verify_source_acquisition(options.fetch(:source_acquisition))
  outputs = build_outputs(
    archive,
    source_acquisition,
    license_review,
    license_review_results
  )
  output_directory = Pathname(options.fetch(:output))

  if options.fetch(:check)
    check_outputs(output_directory, outputs)
    puts "RootFS compliance evidence is reproducible (#{outputs.length} files)."
  else
    write_outputs(output_directory, outputs)
    puts "Generated RootFS compliance evidence in #{output_directory} " \
      "(#{outputs.length} files)."
  end
rescue ComplianceError, OptionParser::ParseError, SystemCallError,
  Gem::Package::TarInvalidError, Zlib::GzipFile::Error, JSON::GeneratorError => error
  warn error.message
  exit 1
end
