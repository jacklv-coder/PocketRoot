#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"

PINNED_VERSION = "v0.3.3"
PINNED_URL =
  "https://github.com/Lolendor/ish-arm64-pkg/releases/download/v0.3.3/fs.tar.gz"
PINNED_SHA256 =
  "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
PINNED_BYTE_COUNT = 6_581_376
PINNED_EXPANDED_BYTE_COUNT = 18_838_016
CANDIDATE_REPOSITORY = "https://github.com/jacklv-coder/ish-arm64-pkg"
SHA256_PATTERN = /\A[0-9a-f]{64}\z/
REVISION_PATTERN = /\A[0-9a-f]{40}\z/

def fail!(message)
  warn "ERROR: #{message}"
  exit 1
end

def real_regular_file(path, label)
  expanded = File.expand_path(path)
  fail!("#{label} is a symbolic link: #{expanded}") if File.symlink?(expanded)
  fail!("#{label} is not a regular file: #{expanded}") unless File.file?(expanded)
  File.realpath(expanded)
rescue Errno::ENOENT, Errno::EACCES => error
  fail!("#{label} is unavailable: #{error.message}")
end

def real_directory(path, label)
  expanded = File.expand_path(path)
  fail!("#{label} is a symbolic link: #{expanded}") if File.symlink?(expanded)
  fail!("#{label} is not a directory: #{expanded}") unless File.directory?(expanded)
  File.realpath(expanded)
rescue Errno::ENOENT, Errno::EACCES => error
  fail!("#{label} is unavailable: #{error.message}")
end

def fetch_hash(value, key, label)
  result = value[key]
  fail!("#{label}.#{key} is missing or is not an object") unless result.is_a?(Hash)
  result
end

def fetch_string(value, key, label, pattern: nil)
  result = value[key]
  fail!("#{label}.#{key} is missing or is not a string") unless result.is_a?(String)
  if pattern && !pattern.match?(result)
    fail!("#{label}.#{key} has an invalid format")
  end
  result
end

def fetch_positive_integer(value, key, label)
  result = value[key]
  unless result.is_a?(Integer) && result.positive?
    fail!("#{label}.#{key} is not a positive integer")
  end
  result
end

def require_equal(actual, expected, label)
  fail!("#{label} does not match the required value") unless actual == expected
end

def digest(path)
  Digest::SHA256.file(path).hexdigest
end

def parse_receipt(path)
  fields = {}
  lines = File.readlines(path, chomp: true)
  fail!("ROOTFS_RECEIPT must contain exactly five fields") unless lines.length == 5
  lines.each do |line|
    key, value = line.split("=", 2)
    fail!("ROOTFS_RECEIPT contains a malformed field") if key.nil? || value.nil?
    fail!("ROOTFS_RECEIPT contains duplicate field #{key}") if fields.key?(key)
    fields[key] = value
  end
  require_equal(fields["ROOTFS_RECEIPT_SCHEMA"], "1", "ROOTFS_RECEIPT schema")
  %w[
    ROOTFS_RECIPE_SHA256
    ROOTFS_IDENTITY_SHA256
    ROOTFS_TARBALL_SHA256
    ROOTFS_SUMS_SHA256
  ].each do |key|
    fail!("ROOTFS_RECEIPT #{key} is not a SHA-256") unless SHA256_PATTERN.match?(fields[key])
  end
  fields
end

options = {}
OptionParser.new do |parser|
  parser.banner =
    "usage: prepare-rootfs-smoke-manifest.rb --archive PATH --output PATH " \
    "--repository-root PATH [--candidate-directory PATH]"
  parser.on("--archive PATH") { |value| options[:archive] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
  parser.on("--repository-root PATH") { |value| options[:repository_root] = value }
  parser.on("--candidate-directory PATH") { |value| options[:candidate_directory] = value }
end.parse!

%i[archive output repository_root].each do |key|
  fail!("missing --#{key.to_s.tr("_", "-")}") if options[key].nil?
end
fail!("unexpected positional arguments") unless ARGV.empty?

archive = real_regular_file(options[:archive], "RootFS archive")
repository_root = real_directory(options[:repository_root], "repository root")
output = File.expand_path(options[:output])
output_parent = real_directory(File.dirname(output), "smoke manifest output parent")
output = File.join(output_parent, File.basename(output))
fail!("smoke manifest output already exists: #{output}") if File.exist?(output) || File.symlink?(output)

manifest = if options[:candidate_directory]
  candidate = real_directory(options[:candidate_directory], "RootFS candidate directory")
  repository_prefix = "#{repository_root}#{File::SEPARATOR}"
  if candidate == repository_root || candidate.start_with?(repository_prefix)
    fail!("RootFS candidate directory must stay outside the repository")
  end

  expected_archive = real_regular_file(
    File.join(candidate, "fs.tar.gz"),
    "candidate fs.tar.gz"
  )
  require_equal(archive, expected_archive, "selected archive path")

  companion_paths = {
    "ROOTFS_IDENTITY" => real_regular_file(
      File.join(candidate, "ROOTFS_IDENTITY"),
      "candidate ROOTFS_IDENTITY"
    ),
    "SHA256SUMS" => real_regular_file(
      File.join(candidate, "SHA256SUMS"),
      "candidate SHA256SUMS"
    ),
    "ROOTFS_RECEIPT" => real_regular_file(
      File.join(candidate, "ROOTFS_RECEIPT"),
      "candidate ROOTFS_RECEIPT"
    )
  }
  metadata_path = real_regular_file(
    File.join(candidate, "ROOTFS_CANDIDATE.json"),
    "candidate metadata"
  )
  metadata = JSON.parse(File.read(metadata_path))
  fail!("candidate metadata is not an object") unless metadata.is_a?(Hash)
  require_equal(metadata["schemaVersion"], 1, "candidate schemaVersion")
  require_equal(
    metadata["status"],
    "local-unapproved-candidate",
    "candidate status"
  )
  require_equal(
    metadata["distributionAuthorized"],
    false,
    "candidate distributionAuthorized"
  )

  reproducibility = fetch_hash(metadata, "reproducibility", "candidate")
  require_equal(reproducibility["buildCount"], 2, "candidate buildCount")
  require_equal(
    reproducibility["comparison"],
    "byte-for-byte",
    "candidate comparison"
  )
  fetch_string(
    reproducibility,
    "sharedHostToolSHA256",
    "candidate.reproducibility",
    pattern: SHA256_PATTERN
  )

  source = fetch_hash(metadata, "source", "candidate")
  require_equal(source["repository"], CANDIDATE_REPOSITORY, "candidate source repository")
  revision = fetch_string(
    source,
    "revision",
    "candidate.source",
    pattern: REVISION_PATTERN
  )
  fetch_string(source, "ishRevision", "candidate.source", pattern: REVISION_PATTERN)
  fetch_string(source, "rootfsPinSHA256", "candidate.source", pattern: SHA256_PATTERN)
  fetch_string(
    source,
    "candidateScriptSHA256",
    "candidate.source",
    pattern: SHA256_PATTERN
  )

  artifacts = fetch_hash(metadata, "artifacts", "candidate")
  rootfs = fetch_hash(artifacts, "fs.tar.gz", "candidate.artifacts")
  rootfs_sha256 = fetch_string(
    rootfs,
    "sha256",
    "candidate.artifacts.fs.tar.gz",
    pattern: SHA256_PATTERN
  )
  rootfs_byte_count = fetch_positive_integer(
    rootfs,
    "size",
    "candidate.artifacts.fs.tar.gz"
  )
  require_equal(digest(archive), rootfs_sha256, "candidate fs.tar.gz SHA-256")
  require_equal(File.size(archive), rootfs_byte_count, "candidate fs.tar.gz byte count")

  artifact_digests = {
    "ROOTFS_IDENTITY" => "ROOTFS_IDENTITY",
    "SHA256SUMS" => "SHA256SUMS",
    "ROOTFS_RECEIPT" => "ROOTFS_RECEIPT"
  }.to_h do |metadata_name, file_name|
    entry = fetch_hash(artifacts, metadata_name, "candidate.artifacts")
    expected = fetch_string(
      entry,
      "sha256",
      "candidate.artifacts.#{metadata_name}",
      pattern: SHA256_PATTERN
    )
    require_equal(
      digest(companion_paths[file_name]),
      expected,
      "candidate #{file_name} SHA-256"
    )
    [file_name, expected]
  end

  require_equal(
    File.read(companion_paths["SHA256SUMS"]),
    "#{rootfs_sha256}  fs.tar.gz\n",
    "candidate SHA256SUMS content"
  )
  receipt = parse_receipt(companion_paths["ROOTFS_RECEIPT"])
  require_equal(
    receipt["ROOTFS_IDENTITY_SHA256"],
    artifact_digests["ROOTFS_IDENTITY"],
    "candidate receipt identity SHA-256"
  )
  require_equal(
    receipt["ROOTFS_TARBALL_SHA256"],
    rootfs_sha256,
    "candidate receipt tarball SHA-256"
  )
  require_equal(
    receipt["ROOTFS_SUMS_SHA256"],
    artifact_digests["SHA256SUMS"],
    "candidate receipt sums SHA-256"
  )

  identity = File.read(companion_paths["ROOTFS_IDENTITY"])
  {
    "ROOTFS_IDENTITY_SCHEMA=3\n" => "candidate RootFS identity schema",
    "ROOTFS_RECIPE=alpine-fakefs-ishsv-v3\n" => "candidate RootFS recipe",
    "ALPINE_VERSION=3.19.1\n" => "candidate Alpine version",
    "ALPINE_ARCH=aarch64\n" => "candidate Alpine architecture",
    "ISH_GUEST_ARCH=arm64\n" => "candidate guest architecture"
  }.each do |line, label|
    fail!("#{label} is missing") unless identity.lines.include?(line)
  end

  {
    "schemaVersion" => 1,
    "source" => "local-unapproved-candidate",
    "distributionAuthorized" => false,
    "version" => "candidate-#{revision[0, 12]}",
    "architecture" => "arm64",
    "format" => "fakefs tar.gz",
    "downloadURL" =>
      "https://invalid.invalid/pocketroot/local-rootfs-candidate/#{revision}/fs.tar.gz",
    "sha256" => rootfs_sha256,
    "archiveByteCount" => rootfs_byte_count,
    "expandedArchiveByteCount" => nil,
    "expectedAlpineVersion" => "3.19.1",
    "sourceRevision" => revision
  }
else
  require_equal(digest(archive), PINNED_SHA256, "pinned RootFS SHA-256")
  require_equal(File.size(archive), PINNED_BYTE_COUNT, "pinned RootFS byte count")
  {
    "schemaVersion" => 1,
    "source" => "pinned-v0.3.3-local-development",
    "distributionAuthorized" => false,
    "version" => PINNED_VERSION,
    "architecture" => "arm64",
    "format" => "fakefs tar.gz",
    "downloadURL" => PINNED_URL,
    "sha256" => PINNED_SHA256,
    "archiveByteCount" => PINNED_BYTE_COUNT,
    "expandedArchiveByteCount" => PINNED_EXPANDED_BYTE_COUNT,
    "expectedAlpineVersion" => "3.19.1",
    "sourceRevision" => nil
  }
end

serialized = JSON.pretty_generate(manifest, quirks_mode: true) + "\n"
File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o644) do |file|
  file.write(serialized)
  file.flush
  file.fsync
end

puts(
  "Prepared #{manifest.fetch("source")} smoke manifest for " \
  "#{manifest.fetch("version")} (#{manifest.fetch("sha256")}, " \
  "#{manifest.fetch("archiveByteCount")} bytes)."
)
