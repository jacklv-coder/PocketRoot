#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "find"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "securerandom"
require_relative "rootfs-license-review"

LicenseReviewError = RootFSLicenseReview::ValidationError
MAX_CANDIDATE_BYTES = 8 * 1_024 * 1_024
MAX_SUBPROCESS_STDERR_BYTES = 64 * 1_024

def parse_options
  options = {
    review_manifest: "Compliance/RootFS/v0.3.3/LICENSE-REVIEW.json",
    source_manifest: "Compliance/RootFS/v0.3.3/SOURCE-ACQUISITION.json",
    source_inventory: "Compliance/RootFS/v0.3.3/SOURCE-INVENTORY.json",
    validate_only: false
  }
  parser = OptionParser.new do |commands|
    commands.banner =
      "Usage: ruby Scripts/prepare-rootfs-license-review.rb [options]"
    commands.on("--review-manifest PATH", "Pinned license-review manifest") do |value|
      options[:review_manifest] = value
    end
    commands.on("--source-manifest PATH", "Pinned source-acquisition manifest") do |value|
      options[:source_manifest] = value
    end
    commands.on("--source-inventory PATH", "Generated source inventory") do |value|
      options[:source_inventory] = value
    end
    commands.on("--source-bundle DIR", "Verified external source-review bundle") do |value|
      options[:source_bundle] = value
    end
    commands.on("--output DIR", "New absolute review directory outside the repository") do |value|
      options[:output] = value
    end
    commands.on("--verify DIR", "Verify an external license-review directory") do |value|
      options[:verify] = value
    end
    commands.on("--validate-only", "Validate manifests without reading source payloads") do
      options[:validate_only] = true
    end
  end
  parser.parse!
  raise OptionParser::InvalidOption, ARGV.join(" ") unless ARGV.empty?

  selected_modes = [
    options[:validate_only],
    !options[:output].nil?,
    !options[:verify].nil?
  ].count(true)
  unless selected_modes == 1
    raise OptionParser::InvalidOption,
      "select exactly one of --validate-only, --output, or --verify"
  end
  if !options[:validate_only] && options[:source_bundle].nil?
    raise OptionParser::MissingArgument, "--source-bundle"
  end

  options
end

def repository_root
  Pathname(__dir__).parent.realpath
end

def within_path?(candidate, parent)
  candidate == parent || candidate.to_s.start_with?("#{parent}#{File::SEPARATOR}")
end

def validate_external_new_output(value)
  output = Pathname(value)
  raise LicenseReviewError, "--output must be absolute" unless output.absolute?
  raise LicenseReviewError, "--output already exists: #{output}" if output.exist? || output.symlink?
  raise LicenseReviewError, "output parent is not a directory" unless output.parent.directory?

  resolved = output.parent.realpath.join(output.basename)
  if within_path?(resolved, repository_root)
    raise LicenseReviewError, "--output must be outside the repository"
  end

  resolved
end

def resolve_external_directory(value, label)
  directory = Pathname(value)
  raise LicenseReviewError, "#{label} must be absolute" unless directory.absolute?
  raise LicenseReviewError, "#{label} must not be a symlink" if directory.symlink?
  raise LicenseReviewError, "#{label} is not a directory" unless directory.directory?

  resolved = directory.realpath
  if within_path?(resolved, repository_root)
    raise LicenseReviewError, "#{label} must be outside the repository"
  end
  resolved
end

def require_regular_file(root, relative, label)
  unless RootFSLicenseReview.safe_relative_path?(relative)
    raise LicenseReviewError, "#{label} has an unsafe path"
  end

  current = root
  relative.split("/").each do |component|
    current = current.join(component)
    raise LicenseReviewError, "#{label} must not contain a symlink" if current.symlink?
  end
  unless current.exist? && current.lstat.file?
    raise LicenseReviewError, "#{label} is not a regular file"
  end
  current
end

def read_limited(stream, maximum_bytes)
  contents = +"".b
  truncated = false
  while (chunk = stream.read(64 * 1_024))
    if contents.bytesize + chunk.bytesize <= maximum_bytes
      contents << chunk
    else
      remaining = maximum_bytes - contents.bytesize
      contents << chunk.byteslice(0, remaining) if remaining.positive?
      truncated = true
    end
  end
  [contents, truncated]
end

def extract_archive_member(archive, member, maximum_bytes)
  output = +"".b
  stderr_result = nil
  exceeded = false
  status = nil
  Open3.popen3("tar", "-xOf", archive.to_s, "--", member) do |stdin, stdout, stderr, wait|
    stdin.close
    stderr_thread = Thread.new do
      read_limited(stderr, MAX_SUBPROCESS_STDERR_BYTES)
    end
    begin
      while (chunk = stdout.read(64 * 1_024))
        output << chunk
        if output.bytesize > maximum_bytes
          exceeded = true
          Process.kill("TERM", wait.pid)
          break
        end
      end
    ensure
      stdout.close
      stderr_result = stderr_thread.value
      status = wait.value
    end
  end

  raise LicenseReviewError, "archive member exceeds bounded size: #{member}" if exceeded
  stderr_text, stderr_truncated = stderr_result
  unless status.success?
    suffix = stderr_truncated ? " (stderr truncated)" : ""
    raise LicenseReviewError,
      "failed to extract archive member #{member}: #{stderr_text.strip}#{suffix}"
  end
  output
end

def verify_candidate_bytes(contents, candidate, origin)
  unless contents.bytesize == candidate.fetch("byteCount")
    raise LicenseReviewError, "candidate byte count mismatch for #{origin}/#{candidate.fetch("outputPath")}"
  end
  unless Digest::SHA256.hexdigest(contents) == candidate.fetch("sha256")
    raise LicenseReviewError, "candidate SHA-256 mismatch for #{origin}/#{candidate.fetch("outputPath")}"
  end
  contents
end

def candidate_bytes(source_bundle, origin, candidate)
  contents =
    case candidate.fetch("sourceKind")
    when "aports-file"
      source = require_regular_file(
        source_bundle,
        candidate.fetch("path"),
        "aports candidate #{origin}"
      )
      if source.size > MAX_CANDIDATE_BYTES
        raise LicenseReviewError, "aports candidate exceeds bounded size for #{origin}"
      end
      source.binread
    when "distfile-member"
      archive = require_regular_file(
        source_bundle,
        "distfiles/#{origin}/#{candidate.fetch("distfile")}",
        "distfile candidate #{origin}"
      )
      extract_archive_member(
        archive,
        candidate.fetch("member"),
        [candidate.fetch("byteCount"), MAX_CANDIDATE_BYTES].min
      )
    else
      raise LicenseReviewError, "unsupported candidate source kind for #{origin}"
    end
  verify_candidate_bytes(contents, candidate, origin)
end

def verify_source_bundle(source_bundle, options)
  command = [
    RbConfig.ruby,
    repository_root.join("Scripts/prepare-rootfs-source-bundle.rb").to_s,
    "--manifest",
    Pathname(options.fetch(:source_manifest)).expand_path.to_s,
    "--source-inventory",
    Pathname(options.fetch(:source_inventory)).expand_path.to_s,
    "--verify",
    source_bundle.to_s
  ]
  stdout, stderr, status = Open3.capture3(*command)
  return if status.success?

  message = stderr.strip.empty? ? stdout.strip : stderr.strip
  raise LicenseReviewError, "source-review bundle verification failed: #{message}"
end

def notice_text(source_count, candidate_count)
  <<~MARKDOWN
    # RootFS license/NOTICE candidate review directory

    This external directory contains #{candidate_count} checksum-verified candidate
    evidence file(s) for #{source_count} source origin(s). The candidates were
    extracted from the pinned, independently verified RootFS source-review bundle.

    This directory is engineering input for package-specific review. It is not a
    completed license bundle, NOTICE set, legal opinion, corresponding-source
    offer, or redistribution approval. Every `openReviewItems` entry in
    `LICENSE-REVIEW.json` remains unresolved.

    Verify this directory against the pinned repository manifests and the original
    external source-review bundle with:

        ruby Scripts/prepare-rootfs-license-review.rb \\
          --source-bundle /absolute/source-review/path \\
          --verify /absolute/license-review/path
  MARKDOWN
end

def review_receipt(review_manifest_bytes, source_acquisition_bytes, entries)
  candidates = entries.flat_map do |entry|
    origin = entry.fetch("sourceOrigin")
    entry.fetch("candidateEvidence").map do |candidate|
      {
        "sourceOrigin" => origin,
        "outputPath" => candidate.fetch("outputPath"),
        "byteCount" => candidate.fetch("byteCount"),
        "sha256" => candidate.fetch("sha256"),
        "reviewState" => "unreviewed-candidate"
      }
    end
  end
  {
    "schemaVersion" => 1,
    "archive" => {
      "version" => RootFSLicenseReview::ARCHIVE_VERSION,
      "sha256" => RootFSLicenseReview::ARCHIVE_SHA256
    },
    "licenseReviewManifestSha256" =>
      Digest::SHA256.hexdigest(review_manifest_bytes),
    "sourceAcquisitionSha256" =>
      Digest::SHA256.hexdigest(source_acquisition_bytes),
    "completeLicenseTextBundlePresent" => false,
    "completePackageNoticeSetPresent" => false,
    "legalReviewApproved" => false,
    "redistributionApproved" => false,
    "candidates" => candidates
  }
end

def expected_payloads(source_bundle, review_manifest_bytes, source_acquisition_bytes, entries)
  payloads = {
    "LICENSE-REVIEW.json" => review_manifest_bytes,
    "NOTICE.md" => notice_text(
      entries.length,
      entries.sum { |entry| entry.fetch("candidateEvidence").length }
    )
  }
  entries.each do |entry|
    origin = entry.fetch("sourceOrigin")
    entry.fetch("candidateEvidence").each do |candidate|
      payloads[candidate.fetch("outputPath")] =
        candidate_bytes(source_bundle, origin, candidate)
    end
  end
  receipt = review_receipt(
    review_manifest_bytes,
    source_acquisition_bytes,
    entries
  )
  payloads["REVIEW-RECEIPT.json"] = "#{JSON.pretty_generate(receipt)}\n"
  payloads
end

def checksum_text(payloads)
  lines = payloads.sort.map do |relative, contents|
    "#{Digest::SHA256.hexdigest(contents)}  #{relative}"
  end
  "#{lines.join("\n")}\n"
end

def materialize_review(output, payloads)
  staging = output.parent.join(".#{output.basename}.staging-#{SecureRandom.hex(8)}")
  raise LicenseReviewError, "staging directory already exists" if staging.exist? || staging.symlink?

  begin
    staging.mkpath
    payloads.each do |relative, contents|
      destination = staging.join(relative)
      destination.dirname.mkpath
      destination.binwrite(contents)
    end
    staging.join("SHA256SUMS").binwrite(checksum_text(payloads))
    File.rename(staging, output)
  ensure
    FileUtils.remove_entry(staging) if staging.exist?
  end
end

def actual_path_types(root)
  path_types = {}
  Find.find(root.to_s) do |value|
    path = Pathname(value)
    next if path == root

    relative = path.relative_path_from(root).to_s
    stat = path.lstat
    if stat.symlink?
      raise LicenseReviewError, "license-review directory contains a symlink: #{relative}"
    elsif stat.directory?
      path_types[relative] = "directory"
    elsif stat.file?
      path_types[relative] = "file"
    else
      raise LicenseReviewError, "license-review directory contains a special node: #{relative}"
    end
  end
  path_types.sort.to_h
end

def expected_path_types(files)
  path_types = files.to_h { |relative| [relative, "file"] }
  files.each do |relative|
    parent = Pathname(relative).dirname
    until parent.to_s == "."
      path_types[parent.to_s] ||= "directory"
      parent = parent.dirname
    end
  end
  path_types.sort.to_h
end

def verify_review(root, payloads)
  expected = payloads.merge("SHA256SUMS" => checksum_text(payloads))
  unless actual_path_types(root) == expected_path_types(expected.keys)
    raise LicenseReviewError,
      "license-review directory path/type set does not match pinned candidates"
  end
  expected.each do |relative, contents|
    path = require_regular_file(root, relative, "license-review file #{relative}")
    unless path.size == contents.bytesize &&
      Digest::SHA256.file(path).hexdigest == Digest::SHA256.hexdigest(contents)
      raise LicenseReviewError, "license-review file does not match pinned bytes: #{relative}"
    end
  end
end

begin
  options = parse_options
  review_manifest_path = Pathname(options.fetch(:review_manifest))
  source_manifest_path = Pathname(options.fetch(:source_manifest))
  review_manifest_bytes = review_manifest_path.binread
  source_acquisition_bytes = source_manifest_path.binread
  review_manifest = JSON.parse(review_manifest_bytes)
  source_acquisition = JSON.parse(source_acquisition_bytes)
  source_inventory = RootFSLicenseReview.load_json(
    options.fetch(:source_inventory),
    "source inventory"
  )
  entries = RootFSLicenseReview.validate_manifest(
    review_manifest,
    source_acquisition,
    source_inventory,
    source_acquisition_bytes: source_acquisition_bytes
  )

  if options.fetch(:validate_only)
    candidate_count =
      entries.sum { |entry| entry.fetch("candidateEvidence").length }
    puts "RootFS license-review manifest is valid " \
      "(#{entries.length} source origins, #{candidate_count} candidates)."
    exit
  end

  source_bundle = resolve_external_directory(
    options.fetch(:source_bundle),
    "--source-bundle"
  )
  verify_source_bundle(source_bundle, options)
  payloads = expected_payloads(
    source_bundle,
    review_manifest_bytes,
    source_acquisition_bytes,
    entries
  )

  if options[:output]
    output = validate_external_new_output(options.fetch(:output))
    materialize_review(output, payloads)
    puts "Materialized RootFS license/NOTICE candidate review at #{output}."
  else
    review = resolve_external_directory(options.fetch(:verify), "--verify")
    verify_review(review, payloads)
    puts "Verified RootFS license/NOTICE candidate review at #{review}."
  end
rescue LicenseReviewError, OptionParser::ParseError, JSON::ParserError,
  SystemCallError => error
  warn error.message
  exit 1
end
