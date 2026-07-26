#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rubygems/package"
require "securerandom"
require "uri"
require "zlib"
require_relative "rootfs-source-acquisition"

SourceBundleError = RootFSSourceAcquisition::ValidationError

MAX_SNAPSHOT_DOWNLOAD_BYTES = 8 * 1_024 * 1_024
MAX_DISTFILE_DOWNLOAD_BYTES = 128 * 1_024 * 1_024
MAX_SNAPSHOT_FILE_BYTES = 16 * 1_024 * 1_024
MAX_SNAPSHOT_TREE_BYTES = 64 * 1_024 * 1_024

def parse_options
  options = {
    manifest: "Compliance/RootFS/v0.3.3/SOURCE-ACQUISITION.json",
    source_inventory: "Compliance/RootFS/v0.3.3/SOURCE-INVENTORY.json",
    validate_only: false
  }

  parser = OptionParser.new do |commands|
    commands.banner =
      "Usage: ruby Scripts/prepare-rootfs-source-bundle.rb [options]"
    commands.on("--manifest PATH", "Pinned source-acquisition manifest") do |path|
      options[:manifest] = path
    end
    commands.on("--source-inventory PATH", "Generated RootFS source inventory") do |path|
      options[:source_inventory] = path
    end
    commands.on("--output DIR", "New absolute directory outside the repository") do |path|
      options[:output] = path
    end
    commands.on(
      "--download-cache DIR",
      "Optional external cache with downloads/aports and distfiles payloads"
    ) do |path|
      options[:download_cache] = path
    end
    commands.on("--validate-only", "Validate manifest without downloading") do
      options[:validate_only] = true
    end
    commands.on("--verify DIR", "Verify a materialized bundle directory") do |path|
      options[:verify] = path
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
  if options[:download_cache] && !options[:output]
    raise OptionParser::InvalidOption,
      "--download-cache requires --output"
  end

  options
end

def load_json(path, label)
  pathname = Pathname(path)
  raise SourceBundleError, "#{label} is not a regular file: #{path}" unless pathname.file?

  JSON.parse(pathname.binread)
rescue JSON::ParserError => error
  raise SourceBundleError, "#{label} is invalid JSON: #{error.message}"
end

def repository_root
  Pathname(__dir__).parent.realpath
end

def within_path?(candidate, parent)
  candidate == parent || candidate.to_s.start_with?("#{parent}#{File::SEPARATOR}")
end

def require_bundle_path(root, relative, label, type:)
  components = safe_tar_relative_path(relative)
  raise SourceBundleError, "#{label} has an unsafe path" unless components

  path = root
  components.each do |component|
    path = path.join(component)
    raise SourceBundleError, "#{label} must not contain a symlink" if path.symlink?
  end
  valid =
    case type
    when :file
      path.exist? && path.lstat.file?
    when :directory
      path.exist? && path.lstat.directory?
    else
      false
    end
  raise SourceBundleError, "#{label} is not a real #{type}" unless valid

  path
end

def resolve_external_directory(path, label)
  directory = Pathname(path)
  raise SourceBundleError, "#{label} must be absolute" unless directory.absolute?
  raise SourceBundleError, "#{label} must not be a symlink" if directory.symlink?
  raise SourceBundleError, "#{label} is not a directory" unless directory.directory?

  resolved = directory.realpath
  if within_path?(resolved, repository_root)
    raise SourceBundleError, "#{label} must be outside the repository"
  end
  resolved
end

def validate_output(path, inputs = [])
  output = Pathname(path)
  raise SourceBundleError, "--output must be absolute" unless output.absolute?
  raise SourceBundleError, "--output already exists: #{output}" if output.exist? || output.symlink?

  parent = output.parent
  raise SourceBundleError, "output parent is not a directory: #{parent}" unless parent.directory?
  resolved_parent = parent.realpath
  resolved_output = resolved_parent.join(output.basename)
  if within_path?(resolved_output, repository_root)
    raise SourceBundleError, "--output must be outside the repository"
  end
  inputs.each do |input|
    if within_path?(resolved_output, input) || within_path?(input, resolved_output)
      raise SourceBundleError,
        "--output must not overlap an input directory"
    end
  end

  resolved_output
end

def copy_cached_download(
  cache,
  relative,
  destination,
  expected_sha512,
  maximum_bytes
)
  source = require_bundle_path(
    cache,
    relative,
    "download cache payload #{relative}",
    type: :file
  )
  if source.size > maximum_bytes
    raise SourceBundleError,
      "download cache payload #{relative} exceeds #{maximum_bytes} bytes"
  end

  destination.dirname.mkpath
  destination.delete if destination.exist?
  digest = Digest::SHA512.new
  source_lstat = source.lstat
  flags = File::RDONLY
  flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
  File.open(source, flags) do |input|
    input_stat = input.stat
    unless input_stat.file? &&
      input_stat.dev == source_lstat.dev &&
      input_stat.ino == source_lstat.ino
      raise SourceBundleError,
        "download cache payload changed while opening: #{relative}"
    end
    File.open(destination, "wb") do |output|
      while (chunk = input.read(64 * 1_024))
        if output.pos + chunk.bytesize > maximum_bytes
          raise SourceBundleError,
            "download cache payload #{relative} exceeds #{maximum_bytes} bytes"
        end
        digest.update(chunk)
        output.write(chunk)
      end
    end
  end
  unless digest.hexdigest == expected_sha512
    raise SourceBundleError,
      "download cache payload #{relative} SHA-512 mismatch"
  end
rescue StandardError
  destination.delete if destination.exist?
  raise
end

def acquire(
  urls,
  destination,
  expected_sha512,
  maximum_bytes,
  cache: nil,
  cache_relative: nil
)
  if cache
    copy_cached_download(
      cache,
      cache_relative,
      destination,
      expected_sha512,
      maximum_bytes
    )
    return {
      "acquisitionMode" => "download-cache",
      "cachePath" => cache_relative
    }
  end

  {
    "acquisitionMode" => "network",
    "selectedURL" =>
      download(urls, destination, expected_sha512, maximum_bytes)
  }
end

def download(urls, destination, expected_sha512, maximum_bytes)
  errors = []
  urls.each do |url|
    destination.dirname.mkpath
    destination.delete if destination.exist?
    uri = URI.parse(url)
    oversized = false
    if uri.scheme == "file"
      source = Pathname(URI.decode_www_form_component(uri.path))
      File.open(source, "rb") do |input|
        File.open(destination, "wb") do |output|
          while (chunk = input.read(64 * 1_024))
            if output.pos + chunk.bytesize > maximum_bytes
              oversized = true
              break
            end
            output.write(chunk)
          end
        end
      end
    else
      command = [
        "curl", "--fail", "--location",
        "--connect-timeout", "15",
        "--max-time", "180",
        "--retry", "2",
        "--retry-all-errors",
        "--max-filesize", maximum_bytes.to_s,
        url
      ]
      stderr_text = nil
      status = nil
      Open3.popen3(*command) do |stdin, stdout, stderr, wait_thread|
        stdin.close
        stderr_reader = Thread.new { stderr.read }
        File.open(destination, "wb") do |output|
          while (chunk = stdout.read(64 * 1_024))
            if output.pos + chunk.bytesize > maximum_bytes
              oversized = true
              begin
                Process.kill("TERM", wait_thread.pid)
              rescue Errno::ESRCH
                # curl exited between the bounded read and termination request.
              end
              break
            end
            output.write(chunk)
          end
        end
        stdout.close unless stdout.closed?
        status = wait_thread.value
        stderr_text = stderr_reader.value
      end
      if oversized
        errors << "#{url}: exceeds #{maximum_bytes} bytes"
        next
      end
      unless status.success?
        errors << "#{url}: #{stderr_text.lines.last&.strip || "curl failed"}"
        next
      end
    end

    if oversized || destination.size > maximum_bytes
      errors << "#{url}: exceeds #{maximum_bytes} bytes"
      next
    end
    actual = Digest::SHA512.file(destination).hexdigest
    return url if actual == expected_sha512

    errors << "#{url}: SHA-512 mismatch (got #{actual})"
  rescue SystemCallError, URI::InvalidURIError => error
    errors << "#{url}: #{error.message}"
  end

  destination.delete if destination.exist?
  raise SourceBundleError, "all retrieval URLs failed for #{destination.basename}: #{errors.join("; ")}"
end

def safe_tar_relative_path(name)
  path = Pathname(name)
  return nil if name.empty? || path.absolute?

  components = path.each_filename.to_a
  return nil if components.empty? || components.any? { |item| item == "." || item == ".." || item.empty? }

  components
end

def resolved_symlink_target(relative, linkname)
  link_path = Pathname(relative)
  link_target = Pathname(linkname)
  resolved_target = link_path.dirname.join(link_target).cleanpath
  if link_target.absolute? ||
    resolved_target.each_filename.any? { |component| component == ".." }
    raise SourceBundleError, "unsafe snapshot symlink target: #{relative} -> #{linkname}"
  end

  resolved_target.to_s
end

def extract_and_verify_snapshot(
  archive,
  destination,
  expected_path,
  expected_count,
  expected_digest
)
  files = []
  symlinks = []
  roots = {}
  total_bytes = 0
  Zlib::GzipReader.open(archive.to_s) do |gzip|
    Gem::Package::TarReader.new(gzip) do |tar|
      tar.each do |entry|
        if %w[g x].include?(entry.header.typeflag)
          next
        end
        if entry.directory? &&
          entry.full_name.match?(/\A[0-9a-f]{40}\.data\/?\z/)
          next
        end
        components = safe_tar_relative_path(entry.full_name)
        raise SourceBundleError, "unsafe tar member: #{entry.full_name}" unless components

        roots[components.first] = true
        next if entry.directory?
        if entry.header.typeflag == "2"
          raise SourceBundleError, "snapshot symlink has no archive root: #{entry.full_name}" if components.length < 2

          symlinks << [components.drop(1).join("/"), entry.header.linkname]
          next
        end
        unless entry.file?
          raise SourceBundleError, "unsupported non-regular tar member: #{entry.full_name}"
        end
        raise SourceBundleError, "snapshot member has no archive root: #{entry.full_name}" if components.length < 2
        if entry.size > MAX_SNAPSHOT_FILE_BYTES
          raise SourceBundleError, "snapshot member is too large: #{entry.full_name}"
        end
        total_bytes += entry.size
        if total_bytes > MAX_SNAPSHOT_TREE_BYTES
          raise SourceBundleError, "snapshot expands beyond the allowed byte limit"
        end

        relative = components.drop(1).join("/")
        contents = entry.read
        mode = entry.header.mode & 0o777
        files << [
          relative,
          Digest::SHA256.hexdigest(contents),
          mode,
          contents
        ]
      end
    end
  end
  raise SourceBundleError, "snapshot must contain exactly one archive root" unless roots.length == 1
  all_paths = files.map(&:first) + symlinks.map(&:first)
  raise SourceBundleError, "snapshot contains duplicate paths" unless all_paths.uniq.length == all_paths.length

  regular_digests = files.to_h do |path, digest, _mode, _contents|
    [path, digest]
  end
  canonical_entries = files.map do |path, digest, mode, _contents|
    ["file", path, format("%04o", mode), digest]
  end
  symlinks.each do |relative, linkname|
    target_relative = resolved_symlink_target(relative, linkname)
    target_digest = regular_digests[target_relative]
    unless target_digest
      raise SourceBundleError,
        "snapshot symlink does not target a regular file: #{relative} -> #{linkname}"
    end

    canonical_entries << [
      "symlink",
      relative,
      linkname,
      target_digest
    ]
  end
  canonical = canonical_entries.sort_by { |entry| entry.fetch(1) }
    .map { |entry| "#{entry.join("\0")}\0" }
    .join
  actual_digest = Digest::SHA256.hexdigest(canonical)
  unless canonical_entries.length == expected_count && actual_digest == expected_digest
    raise SourceBundleError,
      "snapshot tree mismatch for #{archive.basename}: expected #{expected_count} files/" \
      "#{expected_digest}, got #{canonical_entries.length}/#{actual_digest}"
  end

  expected_prefix = "#{expected_path}/"
  files.each do |relative, _digest, mode, contents|
    unless relative.start_with?(expected_prefix) && relative.length > expected_prefix.length
      raise SourceBundleError,
        "snapshot member is outside expected path #{expected_path}: #{relative}"
    end
    target = destination.join(relative.delete_prefix(expected_prefix))
    target.dirname.mkpath
    target.binwrite(contents)
    target.chmod(mode)
  end
  symlinks.each do |relative, linkname|
    unless relative.start_with?(expected_prefix) && relative.length > expected_prefix.length
      raise SourceBundleError,
        "snapshot symlink is outside expected path #{expected_path}: #{relative}"
    end
    link_path = Pathname(relative.delete_prefix(expected_prefix))
    resolved_symlink_target(relative, linkname)

    target = destination.join(link_path)
    target.dirname.mkpath
    raise SourceBundleError, "duplicate snapshot symlink path: #{relative}" if target.exist? || target.symlink?

    File.symlink(linkname, target)
  end

  symlinks
end

def sha256_lines(root)
  root.glob("**/*", File::FNM_DOTMATCH)
    .select { |path| path.lstat.file? }
    .reject { |path| path.relative_path_from(root).to_s == "SHA256SUMS" }
    .map { |path| [path.relative_path_from(root).to_s, Digest::SHA256.file(path).hexdigest] }
    .sort
    .map { |relative, digest| "#{digest}  #{relative}" }
end

def tree_manifest_entries(root)
  root.glob("**/*", File::FNM_DOTMATCH)
    .reject { |path| path == root }
    .map do |path|
      relative = path.relative_path_from(root).to_s
      next if %w[SHA256SUMS TREE-MANIFEST.json].include?(relative)

      if path.symlink?
        {
          "path" => relative,
          "type" => "symlink",
          "target" => path.readlink.to_s
        }
      elsif path.lstat.file?
        {
          "path" => relative,
          "type" => "file",
          "mode" => format("%04o", path.lstat.mode & 0o777),
          "sha256" => Digest::SHA256.file(path).hexdigest
        }
      elsif path.lstat.directory?
        {
          "path" => relative,
          "type" => "directory",
          "mode" => format("%04o", path.lstat.mode & 0o777)
        }
      else
        raise SourceBundleError,
          "bundle contains an unsupported filesystem node: #{relative}"
      end
    end
    .compact
    .uniq { |entry| entry.fetch("path") }
    .sort_by { |entry| entry.fetch("path") }
end

def canonical_materialized_tree(directory, expected_path)
  if directory.symlink? || !directory.directory?
    raise SourceBundleError,
      "materialized aports tree is not a real directory: #{directory}"
  end

  files = {}
  symlinks = []
  directory.glob("**/*", File::FNM_DOTMATCH).each do |entry|
    relative = entry.relative_path_from(directory).to_s
    anchored_path = "#{expected_path}/#{relative}"
    if entry.symlink?
      symlinks << [anchored_path, entry.readlink.to_s]
    elsif entry.lstat.file?
      files[anchored_path] = {
        digest: Digest::SHA256.file(entry).hexdigest,
        mode: entry.lstat.mode & 0o777
      }
    end
  end

  canonical_entries = files.map do |path, identity|
    ["file", path, format("%04o", identity.fetch(:mode)), identity.fetch(:digest)]
  end
  symlinks.each do |anchored_path, target|
    target_path = resolved_symlink_target(anchored_path, target)
    target_identity = files[target_path]
    unless target_identity
      raise SourceBundleError,
        "materialized symlink does not target a regular file: " \
        "#{anchored_path} -> #{target}"
    end
    canonical_entries << [
      "symlink",
      anchored_path,
      target,
      target_identity.fetch(:digest)
    ]
  end
  canonical = canonical_entries.sort_by { |entry| entry.fetch(1) }
    .map { |entry| "#{entry.join("\0")}\0" }
    .join

  {
    count: canonical_entries.length,
    digest: Digest::SHA256.hexdigest(canonical),
    files: files.keys.sort,
    symlinks: symlinks.sort_by(&:first)
  }
end

def expected_bundle_path_types(sources, identities)
  path_types = {
    "MATERIALIZATION-RECEIPT.json" => "file",
    "NOTICE.md" => "file",
    "SOURCE-ACQUISITION.json" => "file"
  }
  sources.each do |source|
    origin = source.fetch("sourceOrigin")
    prefix = "main/#{origin}/"
    path_types["downloads/aports/#{origin}.tar.gz"] = "file"
    identities.fetch(origin).fetch(:files).each do |path|
      unless path.start_with?(prefix)
        raise SourceBundleError,
          "pinned file is outside the expected aports tree: #{path}"
      end
      path_types["aports/#{origin}/#{path.delete_prefix(prefix)}"] = "file"
    end
    identities.fetch(origin).fetch(:symlinks).each do |path, _target|
      unless path.start_with?(prefix)
        raise SourceBundleError,
          "pinned symlink is outside the expected aports tree: #{path}"
      end
      path_types["aports/#{origin}/#{path.delete_prefix(prefix)}"] = "symlink"
    end
    source.fetch("distfiles").each do |distfile|
      path_types["distfiles/#{origin}/#{distfile.fetch("filename")}"] = "file"
    end
  end

  path_types.keys.each do |path|
    parent = Pathname(path).dirname
    until parent.to_s == "."
      path_types[parent.to_s] ||= "directory"
      parent = parent.dirname
    end
  end
  path_types.sort.to_h
end

def verify_receipt(receipt, manifest, sources, root, identities)
  acquisition_mode = receipt["acquisitionMode"]
  unless receipt["schemaVersion"] == 2 &&
    receipt["archive"] == manifest["archive"] &&
    %w[network download-cache].include?(acquisition_mode) &&
    receipt["redistributionApproved"] == false
    raise SourceBundleError, "materialization receipt has invalid release metadata"
  end
  receipt_sources = receipt["sources"]
  unless receipt_sources.is_a?(Array) && receipt_sources.length == sources.length
    raise SourceBundleError, "materialization receipt does not cover every source"
  end

  sources.each_with_index do |source, index|
    origin = source.fetch("sourceOrigin")
    snapshot = source.fetch("aportsSnapshot")
    recorded = receipt_sources[index]
    snapshot_acquisition_valid =
      recorded.is_a?(Hash) &&
        if acquisition_mode == "download-cache"
          !recorded.key?("aportsSnapshotURL") &&
            recorded["aportsCachePath"] ==
              "downloads/aports/#{origin}.tar.gz"
        else
          !recorded.key?("aportsCachePath") &&
            recorded["aportsSnapshotURL"] == snapshot["url"]
        end
    unless recorded.is_a?(Hash) &&
      recorded["sourceOrigin"] == origin &&
      recorded["aportsCommit"] == source["aportsCommit"] &&
      snapshot_acquisition_valid &&
      recorded["aportsCanonicalTreeFormat"] ==
        manifest["aportsCanonicalTreeFormat"] &&
      recorded["aportsCanonicalTreeSha256"] ==
        snapshot["canonicalTreeSha256"]
      raise SourceBundleError,
        "materialization receipt does not match source #{origin}"
    end

    expected_symlinks = identities.fetch(origin).fetch(:symlinks).map do |path, target|
      {
        "path" => path,
        "target" => target
      }
    end
    unless recorded["aportsSymlinks"].is_a?(Array) &&
      recorded["aportsSymlinks"].sort_by { |entry| entry.fetch("path", "") } ==
        expected_symlinks
      raise SourceBundleError,
        "materialization receipt has invalid symlink records for #{origin}"
    end

    recorded_distfiles = recorded["distfiles"]
    expected_distfiles = source.fetch("distfiles")
    unless recorded_distfiles.is_a?(Array) &&
      recorded_distfiles.length == expected_distfiles.length
      raise SourceBundleError,
        "materialization receipt does not cover every distfile for #{origin}"
    end
    expected_distfiles.each_with_index do |distfile, offset|
      distfile_record = recorded_distfiles[offset]
      expected_cache_path =
        "distfiles/#{origin}/#{distfile.fetch("filename")}"
      distfile_acquisition_valid =
        distfile_record.is_a?(Hash) &&
          if acquisition_mode == "download-cache"
            !distfile_record.key?("selectedURL") &&
              distfile_record["cachePath"] == expected_cache_path
          else
            !distfile_record.key?("cachePath") &&
              distfile["retrievalURLs"].include?(
                distfile_record["selectedURL"]
              )
          end
      unless distfile_record.is_a?(Hash) &&
        distfile_record["filename"] == distfile["filename"] &&
        distfile_record["sha512"] == distfile["sha512"] &&
        distfile_acquisition_valid
        raise SourceBundleError,
          "materialization receipt has invalid distfile record for " \
          "#{origin}/#{distfile["filename"]}"
      end
    end
  end

  expected_notice = notice_text(
    manifest,
    sources.length,
    sources.sum { |source| source.fetch("distfiles").length }
  )
  notice_path = require_bundle_path(
    root,
    "NOTICE.md",
    "bundle NOTICE.md",
    type: :file
  )
  unless notice_path.binread == expected_notice
    raise SourceBundleError, "bundle NOTICE.md does not match the pinned manifest"
  end
end

def verify_acquired_sources(root, sources)
  identities = {}
  sources.each do |source|
    origin = source.fetch("sourceOrigin")
    snapshot = source.fetch("aportsSnapshot")
    archive = require_bundle_path(
      root,
      "downloads/aports/#{origin}.tar.gz",
      "bundle snapshot archive #{origin}",
      type: :file
    )
    unless Digest::SHA512.file(archive).hexdigest == snapshot["sha512"]
      raise SourceBundleError,
        "bundle snapshot archive checksum mismatch: #{origin}"
    end

    identity = canonical_materialized_tree(
      require_bundle_path(
        root,
        "aports/#{origin}",
        "materialized aports tree #{origin}",
        type: :directory
      ),
      snapshot.fetch("path")
    )
    unless identity.fetch(:count) == snapshot["regularFileCount"] &&
      identity.fetch(:digest) == snapshot["canonicalTreeSha256"]
      raise SourceBundleError,
        "bundle aports tree does not match the pinned manifest: #{origin}"
    end
    identities[origin] = identity

    source.fetch("distfiles").each do |distfile|
      relative = "distfiles/#{origin}/#{distfile.fetch("filename")}"
      path = require_bundle_path(
        root,
        relative,
        "bundle distfile #{origin}/#{distfile["filename"]}",
        type: :file
      )
      unless Digest::SHA512.file(path).hexdigest == distfile["sha512"]
        raise SourceBundleError,
          "bundle distfile checksum mismatch: #{origin}/#{distfile["filename"]}"
      end
    end
  end

  identities
end

def verify_materialized_bundle(path, manifest_path, source_inventory_path)
  root = Pathname(path)
  raise SourceBundleError, "--verify must be absolute" unless root.absolute?
  if root.symlink? || !root.directory?
    raise SourceBundleError, "bundle is not a real directory: #{root}"
  end

  root = root.realpath
  if within_path?(root, repository_root)
    raise SourceBundleError, "--verify directory must be outside the repository"
  end
  expected_manifest = load_json(
    manifest_path,
    "pinned source acquisition manifest"
  )
  source_inventory = load_json(source_inventory_path, "source inventory")
  allow_file_urls =
    ENV["POCKETROOT_TEST_ALLOW_FILE_URLS"] == "1" &&
    expected_manifest["testFixture"] == true
  sources = RootFSSourceAcquisition.validate_manifest(
    expected_manifest,
    source_inventory,
    allow_file_urls: allow_file_urls
  )
  bundled_manifest_path = require_bundle_path(
    root,
    "SOURCE-ACQUISITION.json",
    "bundle source acquisition manifest",
    type: :file
  )
  bundled_manifest = load_json(
    bundled_manifest_path,
    "bundle source acquisition manifest"
  )
  unless bundled_manifest == expected_manifest
    raise SourceBundleError,
      "bundle source acquisition manifest does not match the pinned manifest"
  end
  identities = verify_acquired_sources(root, sources)
  receipt_path = require_bundle_path(
    root,
    "MATERIALIZATION-RECEIPT.json",
    "materialization receipt",
    type: :file
  )
  receipt = load_json(
    receipt_path,
    "materialization receipt"
  )
  verify_receipt(receipt, expected_manifest, sources, root, identities)

  tree_manifest_path = require_bundle_path(
    root,
    "TREE-MANIFEST.json",
    "bundle tree manifest",
    type: :file
  )
  tree_manifest = load_json(
    tree_manifest_path,
    "bundle tree manifest"
  )
  unless tree_manifest["schemaVersion"] == 1 &&
    tree_manifest["entries"].is_a?(Array)
    raise SourceBundleError, "bundle tree manifest has an invalid schema"
  end
  actual_entries = tree_manifest_entries(root)
  expected_symlinks = sources.flat_map do |source|
    origin = source.fetch("sourceOrigin")
    prefix = "main/#{origin}/"
    identities.fetch(origin).fetch(:symlinks).map do |path, target|
      unless path.start_with?(prefix)
        raise SourceBundleError,
          "pinned symlink is outside the expected aports tree: #{path}"
      end
      {
        "path" => "aports/#{origin}/#{path.delete_prefix(prefix)}",
        "type" => "symlink",
        "target" => target
      }
    end
  end.sort_by { |entry| entry.fetch("path") }
  actual_symlinks = actual_entries
    .select { |entry| entry.fetch("type") == "symlink" }
  unless actual_symlinks == expected_symlinks
    raise SourceBundleError,
      "bundle symlink set does not match the pinned aports trees"
  end
  actual_path_types = actual_entries.to_h do |entry|
    [entry.fetch("path"), entry.fetch("type")]
  end
  unless actual_path_types == expected_bundle_path_types(sources, identities)
    raise SourceBundleError,
      "bundle path/type set does not match the pinned source manifest"
  end
  unless actual_entries == tree_manifest.fetch("entries")
    raise SourceBundleError, "bundle tree does not match TREE-MANIFEST.json"
  end

  checksum_path = require_bundle_path(
    root,
    "SHA256SUMS",
    "bundle SHA256SUMS",
    type: :file
  )
  checksum_entries = {}
  checksum_path.each_line do |line|
    match = line.chomp.match(/\A([0-9a-f]{64})  ([^\0\r\n]+)\z/)
    raise SourceBundleError, "bundle SHA256SUMS contains a malformed line" unless match

    relative = match[2]
    components = safe_tar_relative_path(relative)
    unless components && !checksum_entries.key?(relative)
      raise SourceBundleError, "bundle SHA256SUMS contains an unsafe or duplicate path"
    end
    checksum_entries[relative] = match[1]
  end
  regular_paths = root.glob("**/*", File::FNM_DOTMATCH)
    .select { |entry| entry.lstat.file? }
    .map { |entry| entry.relative_path_from(root).to_s }
    .reject { |relative| relative == "SHA256SUMS" }
    .sort
  unless checksum_entries.keys.sort == regular_paths
    raise SourceBundleError, "bundle SHA256SUMS does not cover every regular file"
  end
  checksum_entries.each do |relative, expected|
    actual = Digest::SHA256.file(root.join(relative)).hexdigest
    unless actual == expected
      raise SourceBundleError, "bundle checksum mismatch: #{relative}"
    end
  end
end

def notice_text(manifest, source_count, distfile_count)
  <<~MARKDOWN
    # PocketRoot RootFS source-review bundle

    This directory was materialized from `SOURCE-ACQUISITION.json` for the pinned
    RootFS `#{manifest.fetch("archive").fetch("version")}` archive with SHA-256
    `#{manifest.fetch("archive").fetch("sha256")}`.

    It contains verified Alpine aports recipe snapshots for #{source_count} source
    origins and #{distfile_count} checksum-verified upstream distfile(s). The
    original acquisition manifest, a materialization receipt, a typed
    `TREE-MANIFEST.json`, and `SHA256SUMS` are included. Verify regular files,
    their permission bits, directories, and symbolic-link targets with:

        ruby Scripts/prepare-rootfs-source-bundle.rb --verify /absolute/bundle/path

    This is an external, review-ready engineering bundle. It is not legal advice,
    a reviewed package-specific NOTICE, a source-code offer, or redistribution
    approval. Review package copyright notices, required license texts, build
    completeness, modifications, offer mechanics, and distribution scope before
    shipping any RootFS.
  MARKDOWN
end

def materialize(manifest, sources, output, download_cache: nil)
  staging = output.parent.join(".#{output.basename}.tmp-#{Process.pid}-#{SecureRandom.hex(6)}")
  raise SourceBundleError, "staging path already exists: #{staging}" if staging.exist?

  staging.mkpath
  receipt_sources = []
  begin
    sources.each do |entry|
      origin = entry.fetch("sourceOrigin")
      snapshot = entry.fetch("aportsSnapshot")
      snapshot_archive = staging.join("downloads", "aports", "#{origin}.tar.gz")
      snapshot_acquisition = acquire(
        [snapshot.fetch("url")],
        snapshot_archive,
        snapshot.fetch("sha512"),
        MAX_SNAPSHOT_DOWNLOAD_BYTES,
        cache: download_cache,
        cache_relative: "downloads/aports/#{origin}.tar.gz"
      )
      snapshot_symlinks = extract_and_verify_snapshot(
        snapshot_archive,
        staging.join("aports", origin),
        snapshot.fetch("path"),
        snapshot.fetch("regularFileCount"),
        snapshot.fetch("canonicalTreeSha256")
      )
      materialized_identity = canonical_materialized_tree(
        staging.join("aports", origin),
        snapshot.fetch("path")
      )
      unless materialized_identity.fetch(:count) == snapshot["regularFileCount"] &&
        materialized_identity.fetch(:digest) == snapshot["canonicalTreeSha256"]
        raise SourceBundleError,
          "extracted aports tree does not match the pinned manifest: #{origin}"
      end
      unless materialized_identity.fetch(:symlinks) == snapshot_symlinks.sort_by(&:first)
        raise SourceBundleError,
          "extracted aports symlink set changed during materialization: #{origin}"
      end

      receipt_distfiles = entry.fetch("distfiles").map do |distfile|
        destination = staging.join("distfiles", origin, distfile.fetch("filename"))
        distfile_acquisition = acquire(
          distfile.fetch("retrievalURLs"),
          destination,
          distfile.fetch("sha512"),
          MAX_DISTFILE_DOWNLOAD_BYTES,
          cache: download_cache,
          cache_relative:
            "distfiles/#{origin}/#{distfile.fetch("filename")}"
        )
        {
          "filename" => distfile.fetch("filename"),
          "sha512" => distfile.fetch("sha512")
        }.merge(
          distfile_acquisition["acquisitionMode"] == "download-cache" ?
            {"cachePath" => distfile_acquisition.fetch("cachePath")} :
            {"selectedURL" => distfile_acquisition.fetch("selectedURL")}
        )
      end
      receipt_source = {
        "sourceOrigin" => origin,
        "aportsCommit" => entry.fetch("aportsCommit"),
        "aportsCanonicalTreeFormat" =>
          manifest.fetch("aportsCanonicalTreeFormat"),
        "aportsCanonicalTreeSha256" => snapshot.fetch("canonicalTreeSha256"),
        "aportsSymlinks" => snapshot_symlinks.map do |path, target|
          {
            "path" => path,
            "target" => target
          }
        end,
        "distfiles" => receipt_distfiles
      }
      if snapshot_acquisition["acquisitionMode"] == "download-cache"
        receipt_source["aportsCachePath"] =
          snapshot_acquisition.fetch("cachePath")
      else
        receipt_source["aportsSnapshotURL"] =
          snapshot_acquisition.fetch("selectedURL")
      end
      receipt_sources << receipt_source
    end

    staging.join("SOURCE-ACQUISITION.json").binwrite(
      "#{JSON.pretty_generate(manifest)}\n"
    )
    staging.join("NOTICE.md").binwrite(
      notice_text(manifest, sources.length, sources.sum { |entry| entry.fetch("distfiles").length })
    )
    receipt = {
      "schemaVersion" => 2,
      "archive" => manifest.fetch("archive"),
      "acquisitionMode" =>
        download_cache ? "download-cache" : "network",
      "redistributionApproved" => false,
      "sources" => receipt_sources
    }
    staging.join("MATERIALIZATION-RECEIPT.json").binwrite(
      "#{JSON.pretty_generate(receipt)}\n"
    )
    tree_manifest = {
      "schemaVersion" => 1,
      "entries" => tree_manifest_entries(staging)
    }
    staging.join("TREE-MANIFEST.json").binwrite(
      "#{JSON.pretty_generate(tree_manifest)}\n"
    )
    staging.join("SHA256SUMS").binwrite("#{sha256_lines(staging).join("\n")}\n")
    File.rename(staging, output)
  ensure
    FileUtils.remove_entry(staging) if staging.exist?
  end
end

begin
  options = parse_options
  if options[:verify]
    verify_materialized_bundle(
      options.fetch(:verify),
      options.fetch(:manifest),
      options.fetch(:source_inventory)
    )
    puts "Verified materialized RootFS source-review bundle at #{Pathname(options.fetch(:verify)).realpath}."
    exit
  end

  manifest = load_json(options.fetch(:manifest), "source acquisition manifest")
  source_inventory = load_json(options.fetch(:source_inventory), "source inventory")
  allow_file_urls =
    ENV["POCKETROOT_TEST_ALLOW_FILE_URLS"] == "1" &&
    manifest["testFixture"] == true
  sources = RootFSSourceAcquisition.validate_manifest(
    manifest,
    source_inventory,
    allow_file_urls: allow_file_urls
  )

  if options.fetch(:validate_only)
    puts "RootFS source acquisition manifest is valid (#{sources.length} source origins)."
  else
    download_cache =
      if options[:download_cache]
        resolve_external_directory(
          options.fetch(:download_cache),
          "--download-cache"
        )
      end
    output = validate_output(
      options.fetch(:output),
      [download_cache].compact
    )
    materialize(
      manifest,
      sources,
      output,
      download_cache: download_cache
    )
    puts "Materialized verified RootFS source-review bundle at #{output}."
  end
rescue SourceBundleError, OptionParser::ParseError, SystemCallError,
  Gem::Package::TarInvalidError, Zlib::GzipFile::Error => error
  warn error.message
  exit 1
end
