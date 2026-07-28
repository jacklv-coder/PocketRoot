#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "securerandom"
require_relative "pocketroot-deterministic-json"

module PocketRootReleaseArtifactScanner
  SCHEMA_VERSION = 1
  GENERATED_AT = "2026-07-28T00:00:00Z"
  OUTPUT_FILENAMES = %w[
    ARTIFACT-INVENTORY.json
    README.md
    SBOM.spdx.json
    SHA256SUMS
  ].freeze
  MAXIMUM_FILE_COUNT = 10_000
  MAXIMUM_ENTRY_COUNT = 10_000
  MAXIMUM_FILE_BYTES = 1_073_741_824
  MAXIMUM_TOTAL_BYTES = 4_294_967_296
  MAXIMUM_TOOL_OUTPUT_BYTES = 16_777_216
  MAXIMUM_PROPERTY_LIST_BYTES = 16_777_216
  MAXIMUM_MACH_O_COMMAND_BYTES = 16_777_216
  MAXIMUM_MACH_O_COMMAND_COUNT = 65_536
  MACH_O_MAGICS = [
    0xfeedface,
    0xcefaedfe,
    0xfeedfacf,
    0xcffaedfe,
    0xcafebabe,
    0xbebafeca,
    0xcafebabf,
    0xbfbafeca
  ].freeze
  JIT_ENTITLEMENTS = %w[
    com.apple.security.cs.allow-jit
    com.apple.security.cs.allow-unsigned-executable-memory
    com.apple.security.cs.disable-executable-page-protection
  ].freeze
  RELEASE_GATES = {
    "engineeringArtifactBuilt" => true,
    "engineeringArtifactScanned" => true,
    "binaryFilesAnalyzed" => true,
    "signedReleaseArtifact" => false,
    "exportedReleaseArtifact" => false,
    "completeReleaseArtifactSBOM" => false,
    "legalReviewApproved" => false,
    "appStorePolicyApproved" => false,
    "distributionAuthorized" => false
  }.freeze

  class ScanError < StandardError
  end

  CommandResult = Struct.new(:stdout, :stderr, :success)

  class SystemRunner
    def initialize(maximum_output_bytes: MAXIMUM_TOOL_OUTPUT_BYTES)
      @maximum_output_bytes = maximum_output_bytes
    end

    def run(command, stdin_data: "")
      stdin = nil
      stdout = nil
      stderr = nil
      wait_thread = nil
      writer = nil
      stdin, stdout, stderr, wait_thread = Open3.popen3(*command)
      [stdin, stdout, stderr].each(&:binmode)
      writer =
        Thread.new do
          begin
            stdin.write(stdin_data) unless stdin_data.empty?
          rescue Errno::EPIPE, IOError
            nil
          ensure
            stdin.close unless stdin.closed?
          end
        end
      outputs = {stdout => String.new.b, stderr => String.new.b}
      readers = outputs.keys
      until readers.empty?
        IO.select(readers).first.each do |reader|
          begin
            outputs.fetch(reader) << reader.read_nonblock(65_536)
            if outputs.fetch(reader).bytesize > @maximum_output_bytes
              raise ScanError,
                "tool output exceeds #{@maximum_output_bytes} bytes: " \
                "#{command.first}"
            end
          rescue IO::WaitReadable
            next
          rescue EOFError
            readers.delete(reader)
            reader.close
          end
        end
      end
      writer.join
      status = wait_thread.value
      CommandResult.new(
        outputs.fetch(stdout),
        outputs.fetch(stderr),
        status.success?
      )
    rescue Errno::ENOENT => error
      raise ScanError, "required tool is unavailable: #{error.message}"
    ensure
      stdin.close if stdin && !stdin.closed?
      stdout.close if stdout && !stdout.closed?
      stderr.close if stderr && !stderr.closed?
      writer.kill if writer && writer.alive?
      if wait_thread && wait_thread.alive?
        begin
          Process.kill("TERM", wait_thread.pid)
        rescue Errno::ESRCH
          nil
        end
        wait_thread.join(1)
        if wait_thread.alive?
          begin
            Process.kill("KILL", wait_thread.pid)
          rescue Errno::ESRCH
            nil
          end
          wait_thread.join
        end
      end
    end
  end

  module_function

  def repository_root
    Pathname(__dir__).parent.realpath
  end

  def pretty_json(value)
    PocketRootDeterministicJSON.dump(value, error_class: ScanError)
  end

  def outside_repository!(path, label)
    if filesystem_path_within?(path, repository_root)
      raise ScanError, "#{label} must be outside the repository"
    end
  end

  def filesystem_path_within?(candidate, parent)
    parent_path = Pathname(parent)
    return false unless parent_path.exist? || parent_path.symlink?

    parent_stat = parent_path.lstat
    current = Pathname(candidate)
    until current.exist? || current.symlink?
      ancestor = current.parent
      if ancestor == current
        raise ScanError,
          "could not resolve filesystem containment for #{candidate}"
      end
      current = ancestor
    end
    loop do
      current_stat = current.lstat
      if current_stat.dev == parent_stat.dev &&
        current_stat.ino == parent_stat.ino
        return true
      end
      ancestor = current.parent
      return false if ancestor == current

      current = ancestor
    end
  rescue SystemCallError => error
    raise ScanError,
      "could not resolve filesystem containment: #{error.message}"
  end

  def real_external_directory(path, label)
    candidate = Pathname(path)
    raise ScanError, "#{label} must be absolute" unless candidate.absolute?
    if candidate.symlink? || !candidate.exist? || !candidate.lstat.directory?
      raise ScanError, "#{label} must be a real directory: #{candidate}"
    end
    resolved = candidate.realpath
    outside_repository!(resolved, label)
    resolved
  end

  def parse_plist_file(path, runner, label)
    if path.symlink? || !path.exist?
      raise ScanError, "#{label} must be a bounded real regular file"
    end
    stat = path.lstat
    unless stat.file? && stat.size <= MAXIMUM_PROPERTY_LIST_BYTES
      raise ScanError, "#{label} must be a bounded real regular file"
    end
    parse_plist_data(
      snapshot_file(path, stat, label),
      runner,
      label
    )
  end

  def parse_plist_data(contents, runner, label)
    if contents.bytesize > MAXIMUM_PROPERTY_LIST_BYTES
      raise ScanError,
        "#{label} exceeds #{MAXIMUM_PROPERTY_LIST_BYTES} bytes"
    end
    result =
      runner.run(
        ["/usr/bin/plutil", "-convert", "json", "-o", "-", "--", "-"],
        stdin_data: contents
      )
    unless result.success
      raise ScanError, "#{label} is not a readable property list"
    end
    document = JSON.parse(result.stdout)
    unless document.is_a?(Hash)
      raise ScanError, "#{label} must contain a dictionary"
    end
    document
  rescue JSON::ParserError => error
    raise ScanError, "#{label} produced invalid JSON: #{error.message}"
  end

  def safe_relative_path(value, label)
    unless value.is_a?(String) &&
      value.encoding != Encoding::BINARY &&
      value.valid_encoding? &&
      !value.include?("\0") &&
      !value.empty?
      raise ScanError, "#{label} must be a non-empty UTF-8 string"
    end
    relative = Pathname(value)
    if relative.absolute? ||
      relative.each_filename.any? { |component| component == ".." }
      raise ScanError, "#{label} must be a contained relative path"
    end
    relative.cleanpath
  end

  def resolve_application(kind, input_path, runner)
    input = real_external_directory(input_path, "--#{kind}")
    if kind == "app"
      unless input.extname == ".app"
        raise ScanError, "--app must name a .app directory"
      end
      return [input, {"kind" => "app", "applicationRelativePath" => "."}]
    end
    unless input.extname == ".xcarchive"
      raise ScanError, "--xcarchive must name a .xcarchive directory"
    end
    archive_info =
      parse_plist_file(input.join("Info.plist"), runner, "archive Info.plist")
    application_properties = archive_info["ApplicationProperties"]
    unless application_properties.is_a?(Hash)
      raise ScanError,
        "archive ApplicationProperties must contain a dictionary"
    end
    metadata_application_path =
      safe_relative_path(
        application_properties["ApplicationPath"],
        "archive ApplicationPath"
      )
    unless metadata_application_path.each_filename.to_a.first ==
      "Applications"
      raise ScanError,
        "archive ApplicationPath must be below Applications"
    end
    application_path = Pathname("Products").join(metadata_application_path)
    application = input.join(application_path)
    current = input
    application_path.each_filename do |component|
      current = current.join(component)
      if current.symlink?
        raise ScanError, "archive ApplicationPath contains a symlink"
      end
    end
    unless application.exist? && application.lstat.directory?
      raise ScanError, "archive application is missing: #{application_path}"
    end
    resolved_application = application.realpath
    unless resolved_application.to_s.start_with?(
      "#{input}#{File::SEPARATOR}"
    )
      raise ScanError, "archive application escapes the archive"
    end
    unless resolved_application.extname == ".app"
      raise ScanError, "archive ApplicationPath must name a .app directory"
    end
    [
      resolved_application,
      {
        "kind" => "xcarchive",
        "applicationRelativePath" => application_path.to_s
      }
    ]
  end

  def same_file?(stat, expected)
    stat.file? &&
      stat.dev == expected.dev &&
      stat.ino == expected.ino &&
      stat.size == expected.size &&
      stat.mode == expected.mode &&
      stat.mtime == expected.mtime &&
      stat.ctime == expected.ctime
  end

  def same_directory?(stat, expected)
    stat.directory? &&
      stat.dev == expected.dev &&
      stat.ino == expected.ino &&
      stat.mode == expected.mode &&
      stat.mtime == expected.mtime &&
      stat.ctime == expected.ctime
  end

  def digest_stream(file, expected_size, label)
    sha256 = Digest::SHA256.new
    sha1 = Digest::SHA1.new
    magic = nil
    remaining = expected_size
    while remaining.positive?
      chunk = file.read([1_048_576, remaining].min)
      if chunk.nil? || chunk.empty?
        raise ScanError, "artifact file changed during scan: #{label}"
      end
      magic = chunk.byteslice(0, 4) if magic.nil?
      sha256.update(chunk)
      sha1.update(chunk)
      remaining -= chunk.bytesize
    end
    unless file.read(1).nil?
      raise ScanError, "artifact file changed during scan: #{label}"
    end
    [sha256.hexdigest, sha1.hexdigest, magic]
  end

  def digest_file(path, expected_stat, label)
    flags = File::RDONLY | File::NOFOLLOW
    File.open(path, flags) do |file|
      unless same_file?(file.stat, expected_stat)
        raise ScanError, "artifact file changed during scan: #{label}"
      end
      sha256, sha1, _magic =
        digest_stream(file, expected_stat.size, label)
      mach_o = valid_macho_file?(file, expected_stat.size)
      unless same_file?(file.stat, expected_stat)
        raise ScanError, "artifact file changed during scan: #{label}"
      end
      [sha256, sha1, mach_o]
    end
  rescue Errno::ELOOP
    raise ScanError, "artifact file became a symlink: #{label}"
  end

  def snapshot_file(path, expected_stat, label)
    if expected_stat.size > MAXIMUM_PROPERTY_LIST_BYTES
      raise ScanError,
        "#{label} exceeds #{MAXIMUM_PROPERTY_LIST_BYTES} bytes"
    end
    flags = File::RDONLY | File::NOFOLLOW
    File.open(path, flags) do |file|
      unless same_file?(file.stat, expected_stat)
        raise ScanError, "artifact file changed during scan: #{label}"
      end
      contents = file.read(expected_stat.size + 1)
      unless contents.bytesize == expected_stat.size &&
        same_file?(file.stat, expected_stat)
        raise ScanError, "artifact file changed during scan: #{label}"
      end
      contents
    end
  rescue Errno::ELOOP
    raise ScanError, "artifact file became a symlink: #{label}"
  end

  def read_exact_at(file, offset, length)
    return nil if offset.negative? || length.negative?

    file.seek(offset, IO::SEEK_SET)
    contents = file.read(length)
    contents if contents && contents.bytesize == length
  end

  def unsigned_32(contents, offset, byte_order)
    bytes = contents.byteslice(offset, 4)
    return nil unless bytes && bytes.bytesize == 4

    bytes.unpack(byte_order == :big ? "N" : "V").first
  end

  def unsigned_64(contents, offset, byte_order)
    bytes = contents.byteslice(offset, 8)
    return nil unless bytes && bytes.bytesize == 8

    bytes.unpack(byte_order == :big ? "Q>" : "Q<").first
  end

  def valid_thin_macho_at?(file, offset, slice_size)
    magic_bytes = read_exact_at(file, offset, 4)
    return false unless magic_bytes

    configuration =
      case magic_bytes.unpack("N").first
      when 0xfeedface then [:big, 28]
      when 0xcefaedfe then [:little, 28]
      when 0xfeedfacf then [:big, 32]
      when 0xcffaedfe then [:little, 32]
      end
    return false unless configuration

    byte_order, header_size = configuration
    header = read_exact_at(file, offset, header_size)
    return false unless header && slice_size >= header_size

    cpu_type = unsigned_32(header, 4, byte_order)
    file_type = unsigned_32(header, 12, byte_order)
    command_count = unsigned_32(header, 16, byte_order)
    command_bytes = unsigned_32(header, 20, byte_order)
    return false if cpu_type.nil? || cpu_type.zero?
    return false unless (1..12).cover?(file_type)
    return false if command_count.nil? || command_bytes.nil?
    return false if command_count.zero? && command_bytes.positive?
    return false if command_count > MAXIMUM_MACH_O_COMMAND_COUNT ||
      command_bytes > MAXIMUM_MACH_O_COMMAND_BYTES
    return false if command_count.positive? &&
      command_bytes < command_count * 8
    return false if header_size + command_bytes > slice_size

    command_offset = 0
    command_count.times do
      return false if command_offset + 8 > command_bytes

      command_header =
        read_exact_at(
          file,
          offset + header_size + command_offset,
          8
        )
      return false unless command_header
      command_size = unsigned_32(command_header, 4, byte_order)
      return false unless command_size && command_size >= 8 &&
        (command_size % 4).zero? &&
        command_offset + command_size <= command_bytes
      command_offset += command_size
    end

    command_offset == command_bytes
  end

  def valid_fat_macho?(file, file_size, magic)
    configuration =
      case magic
      when 0xcafebabe then [:big, 20]
      when 0xbebafeca then [:little, 20]
      when 0xcafebabf then [:big, 32]
      when 0xbfbafeca then [:little, 32]
      end
    return false unless configuration

    byte_order, entry_size = configuration
    fat_header = read_exact_at(file, 0, 8)
    return false unless fat_header

    architecture_count = unsigned_32(fat_header, 4, byte_order)
    return false unless architecture_count &&
      (1..64).cover?(architecture_count)

    table_size = architecture_count * entry_size
    table_end = 8 + table_size
    return false if table_end > file_size

    table = read_exact_at(file, 8, table_size)
    return false unless table

    ranges = []
    architecture_count.times do |index|
      entry_offset = index * entry_size
      cpu_type = unsigned_32(table, entry_offset, byte_order)
      if entry_size == 20
        slice_offset = unsigned_32(table, entry_offset + 8, byte_order)
        slice_size = unsigned_32(table, entry_offset + 12, byte_order)
        alignment = unsigned_32(table, entry_offset + 16, byte_order)
      else
        slice_offset = unsigned_64(table, entry_offset + 8, byte_order)
        slice_size = unsigned_64(table, entry_offset + 16, byte_order)
        alignment = unsigned_32(table, entry_offset + 24, byte_order)
      end
      return false unless cpu_type && slice_offset && slice_size && alignment
      return false if slice_offset < table_end || slice_size.zero? ||
        slice_offset + slice_size > file_size || alignment > 63
      return false unless (slice_offset % (1 << alignment)).zero?

      ranges.each do |range_start, range_end|
        return false if slice_offset < range_end &&
          range_start < slice_offset + slice_size
      end
      ranges << [slice_offset, slice_offset + slice_size]

      slice_header = read_exact_at(file, slice_offset, 8)
      return false unless slice_header
      slice_magic = slice_header.byteslice(0, 4).unpack("N").first
      slice_byte_order =
        case slice_magic
        when 0xfeedface, 0xfeedfacf then :big
        when 0xcefaedfe, 0xcffaedfe then :little
        end
      return false unless slice_byte_order
      return false unless unsigned_32(
        slice_header,
        4,
        slice_byte_order
      ) == cpu_type
      return false unless valid_thin_macho_at?(
        file,
        slice_offset,
        slice_size
      )
    end
    true
  end

  def valid_macho_file?(file, file_size)
    magic_bytes = read_exact_at(file, 0, 4)
    return false unless magic_bytes

    magic = magic_bytes.unpack("N").first
    if [0xfeedface, 0xcefaedfe, 0xfeedfacf, 0xcffaedfe].include?(magic)
      valid_thin_macho_at?(file, 0, file_size)
    elsif MACH_O_MAGICS.include?(magic)
      valid_fat_macho?(file, file_size, magic)
    else
      false
    end
  end

  def tree_entry_snapshot(relative, stat)
    [
      relative,
      stat.ftype,
      stat.dev,
      stat.ino,
      stat.mode,
      stat.size,
      stat.mtime,
      stat.ctime
    ]
  end

  def stable_child_lstat(directory_path, expected_directory_stat, name, label)
    unless same_directory?(
      directory_path.lstat,
      expected_directory_stat
    )
      raise ScanError, "artifact directory changed during scan: #{label}"
    end
    child_stat = directory_path.join(name).lstat
    unless same_directory?(
      directory_path.lstat,
      expected_directory_stat
    )
      raise ScanError, "artifact directory changed during scan: #{label}"
    end
    child_stat
  end

  def stable_directory_chain!(
    application,
    relative,
    directory_snapshots
  )
    components = Pathname(relative).each_filename.to_a
    components.pop
    current = application
    keys = ["."]
    components.each do |component|
      current = current.join(component)
      keys << current.relative_path_from(application).to_s
    end
    keys.each do |key|
      expected = directory_snapshots.fetch(key)
      current_stat = current_path_for(application, key).lstat
      unless current_stat.directory? &&
        tree_entry_snapshot(key, current_stat) == expected
        raise ScanError,
          "artifact tree changed during scan: directory #{key}"
      end
    end
  rescue KeyError
    raise ScanError, "artifact tree changed during scan: directory set"
  end

  def current_path_for(application, relative)
    relative == "." ? application : application.join(relative)
  end

  def inventory_files(
    application,
    maximum_entry_count: MAXIMUM_ENTRY_COUNT
  )
    files = []
    root_stat = application.lstat
    tree_entries = [tree_entry_snapshot(".", root_stat)]
    total_bytes = 0
    entry_count = 0
    pending_directories = [[application, root_stat]]
    until pending_directories.empty?
      directory_path, expected_directory_stat = pending_directories.pop
      relative = directory_path.relative_path_from(application).to_s
      label = relative == "." ? "application root" : relative
      unless same_directory?(directory_path.lstat, expected_directory_stat)
        raise ScanError, "artifact directory changed during scan: #{label}"
      end
      unless directory_path.readable? && directory_path.executable?
        raise ScanError, "artifact contains an unreadable directory: #{label}"
      end
      child_directories = []
      begin
        Dir.open(directory_path.to_s) do |directory|
          opened_directory = IO.for_fd(directory.fileno, autoclose: false)
          unless same_directory?(
            opened_directory.stat,
            expected_directory_stat
          )
            raise ScanError,
              "artifact directory changed during scan: #{label}"
          end
          directory.each_child do |name|
            entry_count += 1
            if entry_count > maximum_entry_count
              raise ScanError,
                "artifact exceeds #{maximum_entry_count} filesystem entries"
            end
            path = directory_path.join(name)
            stat =
              stable_child_lstat(
                directory_path,
                expected_directory_stat,
                name,
                label
              )
            relative = path.relative_path_from(application).to_s
            unless relative.encoding != Encoding::BINARY &&
              relative.valid_encoding?
              raise ScanError, "artifact path is not valid UTF-8"
            end
            if stat.symlink?
              raise ScanError, "artifact contains a symlink: #{relative}"
            elsif stat.directory?
              tree_entries << tree_entry_snapshot(relative, stat)
              child_directories << [path, stat]
              next
            elsif !stat.file?
              raise ScanError, "artifact contains a special file: #{relative}"
            end
            tree_entries << tree_entry_snapshot(relative, stat)
            if stat.size > MAXIMUM_FILE_BYTES
              raise ScanError,
                "artifact file exceeds #{MAXIMUM_FILE_BYTES} bytes: #{relative}"
            end
            files << [relative, path, stat]
            if files.length > MAXIMUM_FILE_COUNT
              raise ScanError,
                "artifact exceeds #{MAXIMUM_FILE_COUNT} regular files"
            end
            total_bytes += stat.size
            if total_bytes > MAXIMUM_TOTAL_BYTES
              raise ScanError,
                "artifact exceeds #{MAXIMUM_TOTAL_BYTES} total bytes"
            end
          end
          unless same_directory?(
            opened_directory.stat,
            expected_directory_stat
          )
            raise ScanError,
              "artifact directory changed during scan: #{label}"
          end
        end
      rescue SystemCallError => error
        raise ScanError,
          "artifact directory cannot be traversed: #{label}: #{error.message}"
      end
      pending_directories.concat(child_directories.reverse)
    end
    if files.empty?
      raise ScanError, "application bundle contains no regular files"
    end
    [
      files.sort_by(&:first),
      total_bytes,
      tree_entries.sort_by(&:first)
    ]
  end

  def required_tool_output(runner, command, label)
    result = runner.run(command)
    unless result.success
      raise ScanError, "#{label} failed"
    end
    result.stdout
  end

  def parse_architectures(output)
    line = output.lines.map(&:strip).reject(&:empty?).last.to_s
    if line.include?(":")
      line = line.split(":").last
    end
    architectures = line.split(/\s+/).reject(&:empty?).uniq.sort
    if architectures.empty? ||
      architectures.any? { |value| !value.match?(/\A[A-Za-z0-9_]+\z/) }
      raise ScanError, "lipo returned an invalid architecture list"
    end
    architectures
  end

  def parse_dependencies(output)
    header_seen = false
    dependencies = output.lines.map do |line|
      next if line.strip.empty?
      if !line.match?(/\A\s/) && line.match?(/:\s*\z/)
        header_seen = true
        next
      end
      match = line.match(
        /\A\s+(.+?)\s+\(compatibility version [^)]+\)\s*\z/
      )
      unless match
        raise ScanError, "otool returned an unrecognized dependency line"
      end
      dependency = match[1]
      if dependency.empty? || dependency.include?("\0")
        raise ScanError, "otool returned an invalid dependency"
      end
      dependency
    end.compact.uniq.sort
    unless header_seen
      raise ScanError, "otool output is missing a Mach-O header"
    end
    dependencies
  end

  def parse_symbols(output)
    output.lines.map do |line|
      line.strip.split(/\s+/).last.to_s
    end.select do |symbol|
      symbol.start_with?("_")
    end.uniq.sort
  end

  def scan_binary(relative, path, sha256, runner)
    architectures =
      parse_architectures(
        required_tool_output(
          runner,
          ["/usr/bin/lipo", "-archs", path.to_s],
          "lipo for #{relative}"
        )
      )
    dependencies =
      parse_dependencies(
        required_tool_output(
          runner,
          ["/usr/bin/otool", "-L", path.to_s],
          "otool for #{relative}"
        )
      )
    symbols =
      parse_symbols(
        required_tool_output(
          runner,
          ["/usr/bin/nm", "-u", path.to_s],
          "nm for #{relative}"
        )
      )
    strings =
      required_tool_output(
        runner,
        ["/usr/bin/strings", "-a", path.to_s],
        "strings for #{relative}"
      )
    map_jit = strings.lines.any? do |line|
      line.strip.match?(/(?:\A|[^A-Za-z0-9_])MAP_JIT(?:\z|[^A-Za-z0-9_])/)
    end
    {
      "path" => relative,
      "sha256" => sha256,
      "architectures" => architectures,
      "dependencies" => dependencies,
      "undefinedSymbols" => symbols,
      "signature" => signature(path, runner, deep: false),
      "signals" => {
        "mapJITString" => map_jit,
        "privateFrameworkDependencies" =>
          dependencies.select do |dependency|
            dependency.include?("/System/Library/PrivateFrameworks/") ||
              dependency.include?("/PrivateFrameworks/")
          end
      }
    }
  end

  def signature(code_object, runner, deep:)
    display =
      runner.run(["/usr/bin/codesign", "--display", code_object.to_s])
    unless display.success
      unless display.stderr.include?("code object is not signed at all")
        raise ScanError, "codesign could not determine signature state"
      end
      return {
        "status" => "unsigned",
        "valid" => false,
        "entitlements" => {}
      }
    end
    verification_command = ["/usr/bin/codesign", "--verify"]
    verification_command << "--deep" if deep
    verification_command.concat(["--strict", code_object.to_s])
    verification = runner.run(verification_command)
    entitlement_result =
      runner.run(
        [
          "/usr/bin/codesign",
          "--display",
          "--entitlements",
          ":-",
          code_object.to_s
        ]
      )
    unless entitlement_result.success
      raise ScanError, "codesign could not read application entitlements"
    end
    entitlements =
      if !entitlement_result.stdout.empty?
        parse_plist_data(
          entitlement_result.stdout,
          runner,
          "application entitlements"
        )
      else
        {}
      end
    {
      "status" => verification.success ? "signed-valid" : "signed-invalid",
      "valid" => verification.success,
      "entitlements" => canonical_value(entitlements)
    }
  end

  def canonical_value(value)
    case value
    when Hash
      value.keys.sort.to_h do |key|
        unless key.is_a?(String)
          raise ScanError, "property-list dictionary key must be a string"
        end
        [key, canonical_value(value.fetch(key))]
      end
    when Array
      value.map { |child| canonical_value(child) }
    when String, Integer, Float, TrueClass, FalseClass, NilClass
      value
    else
      raise ScanError, "unsupported property-list value: #{value.class}"
    end
  end

  def required_info_string(info, key)
    value = info[key]
    unless value.is_a?(String) && !value.empty?
      raise ScanError, "application Info.plist is missing #{key}"
    end
    value
  end

  def artifact_digest(files, directories)
    digest = Digest::SHA256.new
    directories.each do |directory|
      digest.update("directory\0")
      digest.update(directory.fetch("path"))
      digest.update("\0")
      digest.update(directory.fetch("mode"))
      digest.update("\n")
    end
    files.each do |file|
      digest.update("file\0")
      digest.update(file.fetch("path"))
      digest.update("\0")
      digest.update(file.fetch("sha256"))
      digest.update("\0")
      digest.update(file.fetch("byteCount").to_s)
      digest.update("\0")
      digest.update(file.fetch("mode"))
      digest.update("\n")
    end
    digest.hexdigest
  end

  def build_inventory(kind, input_path, runner: SystemRunner.new,
    expected_bundle_identifier: nil)
    application, input = resolve_application(kind, input_path, runner)
    entries, total_bytes, initial_tree = inventory_files(application)
    directory_snapshots =
      initial_tree.each_with_object({}) do |entry, snapshots|
        snapshots[entry.fetch(0)] = entry if entry.fetch(1) == "directory"
      end
    directory_documents =
      directory_snapshots.values.sort_by(&:first).map do |entry|
        {
          "path" => entry.fetch(0),
          "mode" => format("%04o", entry.fetch(4) & 0o7777)
        }
      end
    file_documents = []
    binary_documents = []
    entries.each do |relative, path, stat|
      stable_directory_chain!(
        application,
        relative,
        directory_snapshots
      )
      sha256, sha1, mach_o = digest_file(path, stat, relative)
      file_documents << {
        "path" => relative,
        "byteCount" => stat.size,
        "mode" => format("%04o", stat.mode & 0o7777),
        "sha1" => sha1,
        "sha256" => sha256,
        "machO" => mach_o
      }
      if file_documents.last.fetch("machO")
        binary_documents << scan_binary(relative, path, sha256, runner)
      end
      stable_directory_chain!(
        application,
        relative,
        directory_snapshots
      )
      unless same_file?(path.lstat, stat)
        raise ScanError, "artifact file changed during scan: #{relative}"
      end
    end
    info_entry = entries.find { |relative, _path, _stat| relative == "Info.plist" }
    unless info_entry
      raise ScanError, "application bundle is missing Info.plist"
    end
    _info_relative, info_path, info_stat = info_entry
    info =
      parse_plist_data(
        snapshot_file(info_path, info_stat, "Info.plist"),
        runner,
        "application Info.plist"
      )
    bundle_identifier = required_info_string(info, "CFBundleIdentifier")
    if expected_bundle_identifier &&
      bundle_identifier != expected_bundle_identifier
      raise ScanError,
        "bundle identifier drifted: expected #{expected_bundle_identifier}, " \
        "found #{bundle_identifier}"
    end
    executable = required_info_string(info, "CFBundleExecutable")
    executable_path = safe_relative_path(executable, "CFBundleExecutable").to_s
    executable_file =
      file_documents.find { |file| file.fetch("path") == executable_path }
    unless executable_file && executable_file.fetch("machO")
      raise ScanError, "CFBundleExecutable is not an inventoried Mach-O file"
    end
    signature_document = signature(application, runner, deep: true)
    code_object_signatures = [
      [".", signature_document]
    ]
    code_object_signatures.concat(
      binary_documents.map do |binary|
        [binary.fetch("path"), binary.fetch("signature")]
      end
    )
    entitlement_keys =
      code_object_signatures.flat_map do |_path, code_signature|
        code_signature.fetch("entitlements").keys
      end.uniq.sort
    private_entitlements =
      entitlement_keys.select { |key| key.start_with?("com.apple.private.") }
    jit_entitlements = entitlement_keys & JIT_ENTITLEMENTS
    invalid_code_objects =
      code_object_signatures.select do |_path, code_signature|
        code_signature.fetch("status") == "signed-invalid"
      end.map(&:first).uniq.sort
    private_frameworks =
      binary_documents.flat_map do |binary|
        binary.dig("signals", "privateFrameworkDependencies").map do |dependency|
          {"binary" => binary.fetch("path"), "dependency" => dependency}
        end
      end
    map_jit_binaries =
      binary_documents.select do |binary|
        binary.dig("signals", "mapJITString")
      end.map { |binary| binary.fetch("path") }
    risk_signals = {
      "invalidSignature" => !invalid_code_objects.empty?,
      "invalidCodeObjects" => invalid_code_objects,
      "jitEntitlements" => jit_entitlements,
      "mapJITBinaries" => map_jit_binaries,
      "privateEntitlements" => private_entitlements,
      "privateFrameworkDependencies" => private_frameworks
    }
    _final_entries, final_total_bytes, final_tree =
      inventory_files(application)
    unless final_tree == initial_tree && final_total_bytes == total_bytes
      raise ScanError, "artifact tree changed during scan"
    end
    {
      "schemaVersion" => SCHEMA_VERSION,
      "generatedAt" => GENERATED_AT,
      "status" => "engineering-artifact-scan-not-distribution-candidate",
      "input" => input,
      "application" => {
        "bundleIdentifier" => bundle_identifier,
        "displayName" =>
          info["CFBundleDisplayName"] || info["CFBundleName"] || executable,
        "executable" => executable_path,
        "shortVersion" => info["CFBundleShortVersionString"],
        "buildVersion" => info["CFBundleVersion"],
        "minimumOSVersion" => info["MinimumOSVersion"],
        "platformName" => info["DTPlatformName"],
        "sdkName" => info["DTSDKName"],
        "deviceFamilies" => Array(info["UIDeviceFamily"])
      },
      "artifact" => {
        "sha256" =>
          artifact_digest(file_documents, directory_documents),
        "directoryCount" => directory_documents.length,
        "fileCount" => file_documents.length,
        "machOFileCount" => binary_documents.length,
        "totalByteCount" => total_bytes
      },
      "limits" => {
        "maximumFileCount" => MAXIMUM_FILE_COUNT,
        "maximumFileBytes" => MAXIMUM_FILE_BYTES,
        "maximumTotalBytes" => MAXIMUM_TOTAL_BYTES,
        "maximumPropertyListBytes" => MAXIMUM_PROPERTY_LIST_BYTES,
        "maximumMachOCommandBytes" => MAXIMUM_MACH_O_COMMAND_BYTES,
        "maximumMachOCommandCount" => MAXIMUM_MACH_O_COMMAND_COUNT
      },
      "signature" => signature_document,
      "riskSignals" => risk_signals,
      "directories" => directory_documents,
      "files" => file_documents,
      "machOBinaries" => binary_documents,
      "coverage" => RELEASE_GATES.dup
    }
  end

  def clean_engineering_signals?(inventory)
    signals = inventory.fetch("riskSignals")
    !signals.fetch("invalidSignature") &&
      signals.fetch("jitEntitlements").empty? &&
      signals.fetch("mapJITBinaries").empty? &&
      signals.fetch("privateEntitlements").empty? &&
      signals.fetch("privateFrameworkDependencies").empty?
  end

  def spdx_id_for_file(file)
    path_digest = Digest::SHA256.hexdigest(file.fetch("path"))[0, 20]
    "SPDXRef-File-#{path_digest}"
  end

  def build_sbom(inventory)
    files = inventory.fetch("files")
    filename_ordered_sha1s =
      files.sort_by { |file| file.fetch("path") }.
        map { |file| file.fetch("sha1") }
    verification_code =
      Digest::SHA1.hexdigest(filename_ordered_sha1s.join)
    namespace_digest = Digest::SHA256.hexdigest(pretty_json(inventory))
    package_id = "SPDXRef-Package-ScannedApplication"
    spdx_files = files.map do |file|
      {
        "SPDXID" => spdx_id_for_file(file),
        "fileName" => "./#{file.fetch("path")}",
        "checksums" => [
          {"algorithm" => "SHA1", "checksumValue" => file.fetch("sha1")},
          {"algorithm" => "SHA256", "checksumValue" => file.fetch("sha256")}
        ],
        "licenseConcluded" => "NOASSERTION",
        "copyrightText" => "NOASSERTION"
      }
    end
    {
      "spdxVersion" => "SPDX-2.3",
      "dataLicense" => "CC0-1.0",
      "SPDXID" => "SPDXRef-DOCUMENT",
      "name" =>
        "PocketRoot engineering artifact scan - " \
        "#{inventory.dig("application", "bundleIdentifier")}",
      "documentNamespace" =>
        "https://pocketroot.invalid/spdx/artifact-scan/#{namespace_digest}",
      "creationInfo" => {
        "created" => GENERATED_AT,
        "creators" => ["Tool: PocketRoot release-artifact scanner/1"]
      },
      "documentDescribes" => [package_id],
      "packages" => [
        {
          "SPDXID" => package_id,
          "name" => inventory.dig("application", "bundleIdentifier"),
          "versionInfo" =>
            inventory.dig("application", "shortVersion") || "NOASSERTION",
          "supplier" => "NOASSERTION",
          "downloadLocation" => "NOASSERTION",
          "filesAnalyzed" => true,
          "packageVerificationCode" => {
            "packageVerificationCodeValue" => verification_code
          },
          "licenseConcluded" => "NOASSERTION",
          "licenseDeclared" => "NOASSERTION",
          "copyrightText" => "NOASSERTION",
          "primaryPackagePurpose" => "APPLICATION",
          "sourceInfo" =>
            "Ephemeral engineering .app scan; not an exported, signed, " \
            "or distribution-authorized release artifact."
        }
      ],
      "files" => spdx_files,
      "relationships" => spdx_files.map do |file|
        {
          "spdxElementId" => package_id,
          "relationshipType" => "CONTAINS",
          "relatedSpdxElement" => file.fetch("SPDXID")
        }
      end
    }
  end

  def readme(inventory)
    signals = inventory.fetch("riskSignals")
    <<~MARKDOWN
      # PocketRoot engineering artifact scan

      This directory is deterministic evidence for one externally built
      application bundle. It is not a signed/exported release, legal approval,
      App Store approval, or distribution authorization.

      - Bundle identifier: `#{inventory.dig("application", "bundleIdentifier")}`
      - Input kind: `#{inventory.dig("input", "kind")}`
      - Files: #{inventory.dig("artifact", "fileCount")}
      - Mach-O files: #{inventory.dig("artifact", "machOFileCount")}
      - Signature status: `#{inventory.dig("signature", "status")}`
      - Private entitlement signals: #{signals.fetch("privateEntitlements").length}
      - JIT entitlement signals: #{signals.fetch("jitEntitlements").length}
      - `MAP_JIT` binary signals: #{signals.fetch("mapJITBinaries").length}
      - Private framework dependency signals: #{signals.fetch("privateFrameworkDependencies").length}

      `ARTIFACT-INVENTORY.json` records the bundle tree, hashes, Mach-O
      architectures/dependencies/symbols, entitlements, and scan gates.
      `SBOM.spdx.json` is an SPDX 2.3 file inventory for this engineering
      artifact only. `SHA256SUMS` authenticates the generated evidence files.

      中文说明：本目录只记录一个外部构建 App 的确定性工程扫描证据，不代表最终
      签名/导出制品、法律批准、App Store 批准或分发授权。
    MARKDOWN
  end

  def validate_inventory(inventory)
    directories = inventory.fetch("directories")
    files = inventory.fetch("files")
    binaries = inventory.fetch("machOBinaries")
    unless inventory.fetch("schemaVersion") == SCHEMA_VERSION &&
      inventory.fetch("generatedAt") == GENERATED_AT &&
      inventory.fetch("status") ==
        "engineering-artifact-scan-not-distribution-candidate" &&
      inventory.fetch("coverage") == RELEASE_GATES &&
      inventory.dig("artifact", "directoryCount") == directories.length &&
      inventory.dig("artifact", "fileCount") == files.length &&
      inventory.dig("artifact", "machOFileCount") == binaries.length &&
      directories.map { |directory| directory.fetch("path") } ==
        directories.map { |directory| directory.fetch("path") }.sort &&
      directories.map { |directory| directory.fetch("path") }.uniq.length ==
        directories.length &&
      files.map { |file| file.fetch("path") } ==
        files.map { |file| file.fetch("path") }.sort &&
      files.map { |file| file.fetch("path") }.uniq.length == files.length &&
      artifact_digest(files, directories) ==
        inventory.dig("artifact", "sha256")
      raise ScanError, "artifact inventory structure or digest drifted"
    end
    directories.each do |directory|
      unless directory.fetch("mode").match?(/\A[0-7]{4}\z/)
        raise ScanError,
          "artifact inventory contains invalid directory metadata"
      end
    end
    file_hashes = files.to_h do |file|
      unless file.fetch("sha1").match?(/\A[0-9a-f]{40}\z/) &&
        file.fetch("sha256").match?(/\A[0-9a-f]{64}\z/) &&
        file.fetch("byteCount").is_a?(Integer) &&
        file.fetch("byteCount") >= 0
        raise ScanError, "artifact inventory contains invalid file metadata"
      end
      [file.fetch("path"), file.fetch("sha256")]
    end
    binaries.each do |binary|
      unless file_hashes.fetch(binary.fetch("path")) ==
        binary.fetch("sha256")
        raise ScanError, "Mach-O inventory is not bound to the file inventory"
      end
    end
    true
  rescue KeyError, TypeError => error
    raise ScanError, "artifact inventory is incomplete: #{error.message}"
  end

  def validate_sbom(sbom, inventory)
    unless sbom == build_sbom(inventory)
      raise ScanError, "artifact SPDX document content drifted"
    end
    true
  end

  def build_outputs(kind, input_path, runner: SystemRunner.new,
    expected_bundle_identifier: nil)
    inventory =
      build_inventory(
        kind,
        input_path,
        runner: runner,
        expected_bundle_identifier: expected_bundle_identifier
      )
    validate_inventory(inventory)
    sbom = build_sbom(inventory)
    validate_sbom(sbom, inventory)
    outputs = {
      "ARTIFACT-INVENTORY.json" => pretty_json(inventory),
      "README.md" => readme(inventory),
      "SBOM.spdx.json" => pretty_json(sbom)
    }
    outputs["SHA256SUMS"] =
      outputs.sort.map do |filename, contents|
        "#{Digest::SHA256.hexdigest(contents)}  #{filename}"
      end.join("\n") + "\n"
    outputs
  end

  def resolved_new_output(path)
    output = Pathname(path)
    raise ScanError, "--output must be absolute" unless output.absolute?
    if output.exist? || output.symlink?
      raise ScanError, "--output already exists: #{output}"
    end
    unless output.parent.directory? && !output.parent.symlink?
      raise ScanError, "--output parent must be a real directory"
    end
    resolved = output.parent.realpath.join(output.basename)
    outside_repository!(resolved, "--output")
    if resolved.exist? || resolved.symlink?
      raise ScanError, "--output already exists: #{resolved}"
    end
    resolved
  end

  def within_path?(candidate, parent)
    filesystem_path_within?(candidate, parent)
  end

  def reject_evidence_input_overlap!(evidence, kind, input_path)
    input = real_external_directory(input_path, "--#{kind}")
    if within_path?(evidence, input) || within_path?(input, evidence)
      raise ScanError, "artifact evidence must not overlap the scanned input"
    end
  end

  def materialize(path, kind, input_path, runner: SystemRunner.new,
    expected_bundle_identifier: nil)
    output = resolved_new_output(path)
    reject_evidence_input_overlap!(output, kind, input_path)
    staging =
      output.parent.join(".#{output.basename}.staging-#{SecureRandom.hex(8)}")
    begin
      staging.mkdir(0o700)
      build_outputs(
        kind,
        input_path,
        runner: runner,
        expected_bundle_identifier: expected_bundle_identifier
      ).each do |filename, contents|
        destination = staging.join(filename)
        destination.binwrite(contents)
        destination.chmod(0o600)
      end
      File.rename(staging, output)
    ensure
      FileUtils.remove_entry(staging) if staging.exist?
    end
    output
  end

  def verify(path, kind, input_path, runner: SystemRunner.new,
    expected_bundle_identifier: nil, require_clean: false)
    output = real_external_directory(path, "--verify")
    reject_evidence_input_overlap!(output, kind, input_path)
    actual_files = output.children.map { |child| child.basename.to_s }.sort
    unless actual_files == OUTPUT_FILENAMES.sort
      raise ScanError, "artifact evidence file set drifted"
    end
    outputs =
      build_outputs(
        kind,
        input_path,
        runner: runner,
        expected_bundle_identifier: expected_bundle_identifier
      )
    outputs.each do |filename, contents|
      evidence = output.join(filename)
      unless exact_file_contents?(evidence, contents.b)
        raise ScanError, "artifact evidence is stale: #{filename}"
      end
    end
    if require_clean
      inventory = JSON.parse(outputs.fetch("ARTIFACT-INVENTORY.json"))
      unless clean_engineering_signals?(inventory)
        raise ScanError, "artifact contains blocked engineering risk signals"
      end
    end
    true
  end

  def exact_file_contents?(path, expected)
    return false if path.symlink? || !path.exist? || !path.lstat.file?
    flags = File::RDONLY | File::NOFOLLOW
    File.open(path, flags) do |file|
      stat = file.stat
      return false unless stat.file? && stat.size == expected.bytesize
      file.read(expected.bytesize + 1) == expected
    end
  rescue Errno::EACCES, Errno::ELOOP, Errno::ENOENT
    false
  end

  def parse_options(arguments)
    options = {require_clean: false}
    parser = OptionParser.new do |commands|
      commands.banner =
        "Usage: ruby Scripts/scan-release-artifact.rb [options]"
      commands.on("--app PATH", "Scan an external .app directory") do |value|
        options[:app] = value
      end
      commands.on(
        "--xcarchive PATH",
        "Scan the application inside an external .xcarchive"
      ) do |value|
        options[:xcarchive] = value
      end
      commands.on("--output DIR", "Create a new external evidence directory") do |value|
        options[:output] = value
      end
      commands.on("--verify DIR", "Verify an existing evidence directory") do |value|
        options[:verify] = value
      end
      commands.on(
        "--expected-bundle-identifier ID",
        "Require the exact application bundle identifier"
      ) do |value|
        options[:expected_bundle_identifier] = value
      end
      commands.on(
        "--require-clean",
        "Fail verification when private API/JIT/signature risk signals exist"
      ) do
        options[:require_clean] = true
      end
    end
    parser.parse!(arguments)
    raise OptionParser::InvalidOption, arguments.join(" ") unless arguments.empty?
    inputs = [options[:app], options[:xcarchive]].compact
    modes = [options[:output], options[:verify]].compact
    unless inputs.length == 1 && modes.length == 1
      raise OptionParser::InvalidOption,
        "select exactly one input and one of --output or --verify"
    end
    if options.fetch(:require_clean) && !options[:verify]
      raise OptionParser::InvalidOption,
        "--require-clean is only valid with --verify"
    end
    options
  end

  def execute(arguments)
    options = parse_options(arguments)
    kind = options[:app] ? "app" : "xcarchive"
    input_path = options.fetch(kind.to_sym)
    if options[:output]
      output =
        materialize(
          options.fetch(:output),
          kind,
          input_path,
          expected_bundle_identifier:
            options[:expected_bundle_identifier]
        )
      puts "Materialized engineering artifact scan at #{output}."
    else
      verify(
        options.fetch(:verify),
        kind,
        input_path,
        expected_bundle_identifier: options[:expected_bundle_identifier],
        require_clean: options.fetch(:require_clean)
      )
      puts "Engineering artifact scan is reproducible and valid."
    end
    0
  rescue ScanError, OptionParser::ParseError, SystemCallError => error
    warn error.message
    1
  end
end

if $PROGRAM_NAME == __FILE__
  exit PocketRootReleaseArtifactScanner.execute(ARGV)
end
