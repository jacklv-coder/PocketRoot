#!/usr/bin/env ruby

require "base64"
require "digest"
require "fileutils"
require "find"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "rubygems/package"
require "securerandom"
require "stringio"
require_relative "rootfs-corresponding-source-review-results"
require_relative "rootfs-license-notice-review-results"
require_relative "rootfs-rebuild-delivery-evidence"

module RootFSDeliveryCandidate
  ARCHIVE_VERSION = "v0.3.3"
  ARCHIVE_SHA256 =
    "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
  MAX_COMMAND_OUTPUT_BYTES = 16 * 1_024 * 1_024
  MAX_GIT_BLOB_BYTES = 256 * 1_024 * 1_024
  EVIDENCE_FILES = %w[
    SOURCE-DELIVERY-INVENTORY.json
    REBUILD-ENVIRONMENT-REVIEW.json
    SOURCE-ACQUISITION.json
    SOURCE-INVENTORY.json
    CORRESPONDING-SOURCE-REVIEW-RESULTS.json
    LICENSE-NOTICE-CANDIDATES.json
    LICENSE-NOTICE-REVIEW-RESULTS.json
    LICENSE-REVIEW-RESULTS.json
    LICENSE-REVIEW.json
  ].freeze
  EVIDENCE_OPTIONS = {
    inventory: "SOURCE-DELIVERY-INVENTORY.json",
    rebuild_review: "REBUILD-ENVIRONMENT-REVIEW.json",
    source_acquisition: "SOURCE-ACQUISITION.json",
    source_inventory: "SOURCE-INVENTORY.json",
    source_review_results: "CORRESPONDING-SOURCE-REVIEW-RESULTS.json",
    license_candidates: "LICENSE-NOTICE-CANDIDATES.json",
    license_notice_review_results: "LICENSE-NOTICE-REVIEW-RESULTS.json",
    license_review_results: "LICENSE-REVIEW-RESULTS.json",
    license_review: "LICENSE-REVIEW.json"
  }.freeze

  class CandidateError < StandardError
  end

  GitTreeNode = Struct.new(:children)

  module_function

  def repository_root
    Pathname(__dir__).parent.realpath
  end

  def default_evidence_path(filename)
    repository_root.join("Compliance/RootFS/v0.3.3", filename).to_s
  end

  def default_evidence_options
    EVIDENCE_OPTIONS.transform_values do |filename|
      default_evidence_path(filename)
    end
  end

  def parse_options(arguments)
    options = default_evidence_options.merge(validate_only: false)
    parser = OptionParser.new do |commands|
      commands.banner =
        "Usage: ruby Scripts/prepare-rootfs-delivery-candidate.rb [options]"
      commands.on("--inventory PATH", "Source-delivery inventory") do |value|
        options[:inventory] = value
      end
      commands.on("--rebuild-review PATH", "Rebuild-environment review") do |value|
        options[:rebuild_review] = value
      end
      commands.on("--source-manifest PATH", "Source-acquisition manifest") do |value|
        options[:source_acquisition] = value
      end
      commands.on("--source-inventory PATH", "Installed-package source inventory") do |value|
        options[:source_inventory] = value
      end
      commands.on(
        "--source-review-results PATH",
        "Corresponding-source engineering review results"
      ) do |value|
        options[:source_review_results] = value
      end
      commands.on("--license-candidates PATH", "LICENSE/NOTICE candidate manifest") do |value|
        options[:license_candidates] = value
      end
      commands.on(
        "--license-notice-review-results PATH",
        "LICENSE/NOTICE candidate review results"
      ) do |value|
        options[:license_notice_review_results] = value
      end
      commands.on(
        "--license-review-results PATH",
        "Package license review results"
      ) do |value|
        options[:license_review_results] = value
      end
      commands.on("--license-review-manifest PATH", "Package license review") do |value|
        options[:license_review] = value
      end
      commands.on("--historical-builder DIR", "Pinned historical builder checkout") do |value|
        options[:historical_builder] = value
      end
      commands.on("--successor-builder DIR", "Pinned successor builder checkout") do |value|
        options[:successor_builder] = value
      end
      commands.on("--alpine-minirootfs FILE", "Pinned Alpine minirootfs input") do |value|
        options[:alpine_minirootfs] = value
      end
      commands.on("--source-bundle DIR", "Verified corresponding-source candidate") do |value|
        options[:source_bundle] = value
      end
      commands.on("--license-notice-bundle DIR", "Verified LICENSE/NOTICE candidate") do |value|
        options[:license_notice_bundle] = value
      end
      commands.on(
        "--license-review-bundle DIR",
        "Verified license-review evidence used to revalidate the NOTICE candidate"
      ) do |value|
        options[:license_review_bundle] = value
      end
      commands.on("--output DIR", "New absolute external candidate directory") do |value|
        options[:output] = value
      end
      commands.on("--verify DIR", "Verify an external delivery candidate") do |value|
        options[:verify] = value
      end
      commands.on("--validate-only", "Validate checked-in manifests only") do
        options[:validate_only] = true
      end
    end
    parser.parse!(arguments)
    raise OptionParser::InvalidOption, arguments.join(" ") unless arguments.empty?

    modes = [
      options.fetch(:validate_only),
      !options[:output].nil?,
      !options[:verify].nil?
    ].count(true)
    unless modes == 1
      raise OptionParser::InvalidOption,
        "select exactly one of --validate-only, --output, or --verify"
    end
    if options[:verify]
      canonical = default_evidence_options
      overridden =
        EVIDENCE_OPTIONS.keys.find do |name|
          Pathname(options.fetch(name)).expand_path !=
            Pathname(canonical.fetch(name)).expand_path
        end
      if overridden
        raise OptionParser::InvalidOption,
          "--verify is bound to checked-in canonical RootFS evidence; " \
          "#{overridden} cannot be overridden"
      end
    end
    if options[:output]
      %i[
        historical_builder successor_builder alpine_minirootfs source_bundle
        license_notice_bundle license_review_bundle
      ].each do |name|
        flag = "--#{name.to_s.tr("_", "-")}"
        raise OptionParser::MissingArgument, flag unless options[name]
      end
    end
    options
  end

  def pretty_json(value)
    "#{JSON.pretty_generate(value)}\n"
  end

  def load_document(path, label)
    pathname = Pathname(path)
    if pathname.symlink? || !pathname.exist? || !pathname.lstat.file?
      raise CandidateError, "#{label} is not a real regular file: #{path}"
    end
    contents = pathname.binread
    {
      path: pathname,
      contents: contents,
      document: JSON.parse(contents)
    }
  rescue JSON::ParserError => error
    raise CandidateError, "#{label} is invalid JSON: #{error.message}"
  end

  def load_documents(options)
    {
      "SOURCE-DELIVERY-INVENTORY.json" =>
        load_document(options.fetch(:inventory), "source-delivery inventory"),
      "REBUILD-ENVIRONMENT-REVIEW.json" =>
        load_document(options.fetch(:rebuild_review), "rebuild-environment review"),
      "SOURCE-ACQUISITION.json" =>
        load_document(options.fetch(:source_acquisition), "source-acquisition manifest"),
      "SOURCE-INVENTORY.json" =>
        load_document(options.fetch(:source_inventory), "source inventory"),
      "CORRESPONDING-SOURCE-REVIEW-RESULTS.json" =>
        load_document(
          options.fetch(:source_review_results),
          "corresponding-source review results"
        ),
      "LICENSE-NOTICE-CANDIDATES.json" =>
        load_document(options.fetch(:license_candidates), "LICENSE/NOTICE candidates"),
      "LICENSE-NOTICE-REVIEW-RESULTS.json" =>
        load_document(
          options.fetch(:license_notice_review_results),
          "LICENSE/NOTICE review results"
        ),
      "LICENSE-REVIEW-RESULTS.json" =>
        load_document(options.fetch(:license_review_results), "license review results"),
      "LICENSE-REVIEW.json" =>
        load_document(options.fetch(:license_review), "license review")
    }
  end

  def load_candidate_documents(root)
    evidence = "evidence"
    paths = EVIDENCE_FILES.to_h do |filename|
      [
        filename,
        require_candidate_file(root, "#{evidence}/#{filename}").to_s
      ]
    end
    load_documents(
      inventory: paths.fetch("SOURCE-DELIVERY-INVENTORY.json"),
      rebuild_review: paths.fetch("REBUILD-ENVIRONMENT-REVIEW.json"),
      source_acquisition: paths.fetch("SOURCE-ACQUISITION.json"),
      source_inventory: paths.fetch("SOURCE-INVENTORY.json"),
      source_review_results:
        paths.fetch("CORRESPONDING-SOURCE-REVIEW-RESULTS.json"),
      license_candidates: paths.fetch("LICENSE-NOTICE-CANDIDATES.json"),
      license_notice_review_results:
        paths.fetch("LICENSE-NOTICE-REVIEW-RESULTS.json"),
      license_review_results: paths.fetch("LICENSE-REVIEW-RESULTS.json"),
      license_review: paths.fetch("LICENSE-REVIEW.json")
    )
  end

  def verify_canonical_evidence(candidate_documents, canonical_documents)
    unless candidate_documents.keys.sort == EVIDENCE_FILES.sort &&
      canonical_documents.keys.sort == EVIDENCE_FILES.sort
      raise CandidateError, "delivery candidate evidence set is incomplete"
    end
    EVIDENCE_FILES.each do |filename|
      unless candidate_documents.fetch(filename).fetch(:contents) ==
        canonical_documents.fetch(filename).fetch(:contents)
        raise CandidateError,
          "delivery candidate evidence does not match checked-in canonical " \
          "evidence: #{filename}"
      end
    end
    true
  rescue KeyError, TypeError
    raise CandidateError, "delivery candidate evidence set is incomplete"
  end

  def sha256(contents)
    Digest::SHA256.hexdigest(contents)
  end

  def validate_archive(document, label)
    archive = document.fetch("archive")
    unless archive.fetch("version") == ARCHIVE_VERSION &&
      archive.fetch("sha256") == ARCHIVE_SHA256
      raise CandidateError, "#{label} does not bind the pinned RootFS archive"
    end
  rescue KeyError, TypeError
    raise CandidateError, "#{label} has an invalid archive binding"
  end

  def validate_documents(documents)
    inventory =
      documents.fetch("SOURCE-DELIVERY-INVENTORY.json").fetch(:document)
    begin
      generated_delivery_evidence =
        RootFSRebuildDeliveryEvidence.build(
          source_acquisition:
            documents.fetch("SOURCE-ACQUISITION.json").fetch(:document),
          source_inventory:
            documents.fetch("SOURCE-INVENTORY.json").fetch(:document),
          corresponding_source_review_results:
            documents
              .fetch("CORRESPONDING-SOURCE-REVIEW-RESULTS.json")
              .fetch(:document),
          source_acquisition_bytes:
            documents.fetch("SOURCE-ACQUISITION.json").fetch(:contents),
          source_inventory_bytes:
            documents.fetch("SOURCE-INVENTORY.json").fetch(:contents),
          corresponding_source_review_results_bytes:
            documents
              .fetch("CORRESPONDING-SOURCE-REVIEW-RESULTS.json")
              .fetch(:contents)
        )
    rescue RootFSRebuildDeliveryEvidence::ValidationError => error
      raise CandidateError,
        "RootFS rebuild/delivery evidence is invalid: #{error.message}"
    end
    %w[
      REBUILD-ENVIRONMENT-REVIEW.json
      SOURCE-DELIVERY-INVENTORY.json
    ].each do |filename|
      unless documents.fetch(filename).fetch(:contents) ==
        generated_delivery_evidence.fetch(filename)
        raise CandidateError,
          "RootFS rebuild/delivery evidence is not reproducible: #{filename}"
      end
    end
    validate_archive(inventory, "source-delivery inventory")
    unless inventory.fetch("schemaVersion") == 1
      raise CandidateError, "source-delivery inventory schema is unsupported"
    end
    units = inventory.fetch("deliveryUnits")
    unless units.is_a?(Array) && units.map { |unit| unit["id"] } == %w[
      historical-rootfs-builder
      successor-rootfs-builder
      alpine-minirootfs-input
      installed-package-corresponding-source
      rootfs-modifications
    ]
      raise CandidateError, "source-delivery inventory has an unexpected unit set"
    end
    unless units.all? do |unit|
      unit["indexed"] == true && unit["materializedForDelivery"] == false
    end
      raise CandidateError,
        "source-delivery inventory must keep checked-in materialization claims false"
    end
    coverage = inventory.fetch("coverage")
    unless coverage.fetch("deliveryUnitCount") == units.length &&
      coverage.fetch("candidateSourceMaterialIndexComplete") == true &&
      coverage.fetch("modificationDisclosureIndexed") == true &&
      coverage.fetch("successorRebuildEvidenceIndexed") == true &&
      coverage.fetch("deliveryCandidateMaterializer") ==
        "Scripts/prepare-rootfs-delivery-candidate.rb" &&
      coverage.fetch("deliveryCandidateMaterializerReady") == true
      raise CandidateError,
        "source-delivery inventory does not declare the current materializer ready"
    end
    %w[
      materializedCorrespondingSourceBundlePresent
      completeLicenseAndNoticeBundlePresent
      sourceOfferPrepared
      deliveryMechanismApproved
      legalReviewApproved
      redistributionApproved
    ].each do |gate|
      unless coverage[gate] == false
        raise CandidateError, "source-delivery inventory release gate is open: #{gate}"
      end
    end
    evidence = inventory.fetch("inputEvidence")
    {
      "SOURCE-ACQUISITION.json" => "SOURCE-ACQUISITION.json",
      "SOURCE-INVENTORY.json" => "SOURCE-INVENTORY.json",
      "CORRESPONDING-SOURCE-REVIEW-RESULTS.json" =>
        "CORRESPONDING-SOURCE-REVIEW-RESULTS.json",
      "REBUILD-ENVIRONMENT-REVIEW.json" => "REBUILD-ENVIRONMENT-REVIEW.json"
    }.each do |key, filename|
      expected = evidence.fetch(key).fetch("sha256")
      actual = sha256(documents.fetch(filename).fetch(:contents))
      unless actual == expected
        raise CandidateError, "source-delivery inventory evidence drift: #{filename}"
      end
    end
    rebuild =
      documents.fetch("REBUILD-ENVIRONMENT-REVIEW.json").fetch(:document)
    validate_archive(rebuild, "rebuild-environment review")
    units_by_id = units.to_h { |unit| [unit.fetch("id"), unit] }
    expected_delivery_sources = {
      "historical-rootfs-builder" =>
        rebuild.fetch("publishedArchiveBuild").fetch("builderSource"),
      "successor-rootfs-builder" =>
        rebuild.fetch("successorCandidateBuild").fetch("builderSource"),
      "alpine-minirootfs-input" =>
        rebuild
          .fetch("successorCandidateBuild")
          .fetch("candidateArtifact")
          .fetch("alpineMinirootfs")
    }
    expected_delivery_sources.each do |unit_id, expected_source|
      unless units_by_id.fetch(unit_id).fetch("source") == expected_source
        raise CandidateError,
          "source-delivery inventory does not match rebuild evidence: #{unit_id}"
      end
    end
    conclusions = rebuild.fetch("conclusions")
    %w[
      correspondingSourceDeliveryApproved
      legalReviewApproved
      redistributionApproved
    ].each do |gate|
      unless conclusions[gate] == false
        raise CandidateError, "rebuild review release gate is open: #{gate}"
      end
    end
    documents.each do |filename, input|
      next if filename == "SOURCE-DELIVERY-INVENTORY.json" ||
        filename == "REBUILD-ENVIRONMENT-REVIEW.json"

      document = input.fetch(:document)
      validate_archive(document, filename) if document.is_a?(Hash) && document.key?("archive")
    end
    begin
      RootFSCorrespondingSourceReviewResults.validate_manifest(
        documents.fetch(
          "CORRESPONDING-SOURCE-REVIEW-RESULTS.json"
        ).fetch(:document),
        documents.fetch("SOURCE-ACQUISITION.json").fetch(:document),
        documents.fetch("SOURCE-INVENTORY.json").fetch(:document),
        source_acquisition_bytes:
          documents.fetch("SOURCE-ACQUISITION.json").fetch(:contents)
      )
      RootFSLicenseNoticeReviewResults.validate_manifest(
        documents.fetch("LICENSE-NOTICE-REVIEW-RESULTS.json").fetch(:document),
        documents.fetch("LICENSE-NOTICE-CANDIDATES.json").fetch(:document),
        prior_results:
          documents.fetch("LICENSE-REVIEW-RESULTS.json").fetch(:document),
        license_review:
          documents.fetch("LICENSE-REVIEW.json").fetch(:document),
        source_acquisition:
          documents.fetch("SOURCE-ACQUISITION.json").fetch(:document),
        source_inventory:
          documents.fetch("SOURCE-INVENTORY.json").fetch(:document),
        candidate_bytes:
          documents.fetch("LICENSE-NOTICE-CANDIDATES.json").fetch(:contents),
        prior_results_bytes:
          documents.fetch("LICENSE-REVIEW-RESULTS.json").fetch(:contents),
        license_review_bytes:
          documents.fetch("LICENSE-REVIEW.json").fetch(:contents),
        source_acquisition_bytes:
          documents.fetch("SOURCE-ACQUISITION.json").fetch(:contents)
      )
    rescue RootFSCorrespondingSourceReviewResults::ValidationError => error
      raise CandidateError,
        "corresponding-source review results are invalid: #{error.message}"
    rescue RootFSLicenseNoticeReviewResults::ValidationError => error
      raise CandidateError,
        "LICENSE/NOTICE review results are invalid: #{error.message}"
    end
    {
      inventory: inventory,
      units: units_by_id
    }
  rescue KeyError, TypeError => error
    raise CandidateError, "delivery evidence is incomplete: #{error.message}"
  end

  def within_path?(candidate, parent)
    candidate == parent ||
      candidate.to_s.start_with?("#{parent}#{File::SEPARATOR}")
  end

  def resolve_external_directory(value, label)
    directory = Pathname(value)
    raise CandidateError, "#{label} must be absolute" unless directory.absolute?
    raise CandidateError, "#{label} must not be a symlink" if directory.symlink?
    raise CandidateError, "#{label} is not a directory" unless directory.directory?

    resolved = directory.realpath
    if within_path?(resolved, repository_root)
      raise CandidateError, "#{label} must be outside the repository"
    end
    resolved
  end

  def resolve_external_file(value, label)
    path = Pathname(value)
    raise CandidateError, "#{label} must be absolute" unless path.absolute?
    if path.symlink? || !path.exist? || !path.lstat.file?
      raise CandidateError, "#{label} is not a real regular file"
    end
    resolved = path.realpath
    if within_path?(resolved, repository_root)
      raise CandidateError, "#{label} must be outside the repository"
    end
    resolved
  end

  def validate_new_output(value, inputs)
    output = Pathname(value)
    raise CandidateError, "--output must be absolute" unless output.absolute?
    if output.exist? || output.symlink?
      raise CandidateError, "--output already exists: #{output}"
    end
    unless output.parent.directory? && !output.parent.symlink?
      raise CandidateError, "--output parent must be a real directory"
    end
    resolved = output.parent.realpath.join(output.basename)
    if within_path?(resolved, repository_root)
      raise CandidateError, "--output must be outside the repository"
    end
    inputs.each do |input|
      if within_path?(resolved, input) || within_path?(input, resolved)
        raise CandidateError, "--output must not overlap an input"
      end
    end
    resolved
  end

  def safe_relative_path?(value)
    return false unless value.is_a?(String) && !value.empty?
    return false if value.start_with?("/", "\\") || value.include?("\0")

    components = value.split("/", -1)
    components.none? { |component| component.empty? || %w[. ..].include?(component) }
  end

  def read_bounded_command_stream(stream, maximum_bytes, wait_thread)
    output = +"".b
    exceeded = false
    loop do
      chunk = stream.readpartial(64 * 1_024)
      remaining = maximum_bytes + 1 - output.bytesize
      output << chunk.byteslice(0, remaining) if remaining.positive?
      next unless output.bytesize > maximum_bytes

      exceeded = true
      begin
        Process.kill("KILL", -wait_thread.pid)
      rescue Errno::ESRCH
        # The command exited between the bounded read and termination request.
      end
      break
    end
    [output, exceeded]
  rescue EOFError
    [output, exceeded]
  ensure
    stream.close unless stream.closed?
  end

  def command_output(
    arguments,
    label,
    chdir: nil,
    maximum_bytes: MAX_COMMAND_OUTPUT_BYTES
  )
    spawn_options = {pgroup: true}
    spawn_options[:chdir] = chdir.to_s if chdir
    popen_arguments = arguments.dup << spawn_options
    stdout_text = nil
    stderr_text = nil
    stdout_exceeded = false
    stderr_exceeded = false
    status = nil
    Open3.popen3(*popen_arguments) do |stdin, stdout, stderr, wait_thread|
      stdin.close
      stdout_reader =
        Thread.new do
          read_bounded_command_stream(stdout, maximum_bytes, wait_thread)
        end
      stderr_reader =
        Thread.new do
          read_bounded_command_stream(stderr, maximum_bytes, wait_thread)
        end
      stdout_text, stdout_exceeded = stdout_reader.value
      stderr_text, stderr_exceeded = stderr_reader.value
      status = wait_thread.value
    end
    if stdout_exceeded || stderr_exceeded
      raise CandidateError, "#{label} output exceeded the safety limit"
    end
    unless status.success?
      message = stderr_text.empty? ? stdout_text : stderr_text
      raise CandidateError, "#{label} failed: #{message.strip}"
    end
    stdout_text
  end

  def git_output(checkout, *arguments)
    command_output(
      ["git", "-C", checkout.to_s, *arguments],
      "git #{arguments.first}"
    )
  end

  def each_git_blob(checkout, entries)
    return if entries.empty?

    Open3.popen3(
      "git",
      "-C",
      checkout.to_s,
      "cat-file",
      "--batch"
    ) do |stdin, stdout, stderr, wait_thread|
      entries.each do |entry|
        object = entry.fetch("object")
        stdin.write("#{object}\n")
        stdin.flush
        header = stdout.gets
        match = header&.match(/\A([0-9a-f]{40,64}) blob ([0-9]+)\n\z/)
        unless match && match[1] == object
          raise CandidateError, "git cat-file returned an invalid blob header"
        end
        byte_count = Integer(match[2], 10)
        if byte_count > MAX_GIT_BLOB_BYTES
          raise CandidateError, "git blob exceeds the safety limit: #{object}"
        end
        contents = stdout.read(byte_count)
        unless contents && contents.bytesize == byte_count && stdout.read(1) == "\n"
          raise CandidateError, "git cat-file returned a truncated blob: #{object}"
        end
        yield entry, contents
      end
      stdin.close
      error_output = stderr.read(MAX_COMMAND_OUTPUT_BYTES + 1) || ""
      if error_output.bytesize > MAX_COMMAND_OUTPUT_BYTES
        raise CandidateError, "git cat-file stderr exceeded the safety limit"
      end
      unless wait_thread.value.success?
        raise CandidateError, "git cat-file failed: #{error_output.strip}"
      end
    end
  end

  def parse_git_tree(checkout, revision)
    output = git_output(checkout, "ls-tree", "-rz", revision)
    output.split("\0", -1).reject(&:empty?).map do |record|
      metadata, path = record.split("\t", 2)
      mode, type, object = metadata.to_s.split(" ", 3)
      unless path && safe_relative_path?(path) &&
        mode&.match?(/\A[0-7]{6}\z/) &&
        %w[blob commit].include?(type) &&
        object&.match?(/\A[0-9a-f]{40,64}\z/)
        raise CandidateError, "git tree contains an unsafe or malformed entry"
      end
      {
        "path" => path,
        "mode" => mode,
        "type" => type,
        "object" => object
      }
    end
  end

  def git_tree_directories(entries)
    directories = {}
    entries.each do |entry|
      path = Pathname(entry.fetch("path"))
      parent = path.dirname
      until parent.to_s == "."
        directories[parent.to_s] = true
        parent = parent.dirname
      end
      directories[path.to_s] = true if entry.fetch("type") == "commit"
    end
    directories.keys.sort_by { |path| [path.count("/"), path] }
  end

  def pax_record(key, value)
    payload = "#{key}=#{value}\n".b
    length = payload.bytesize + 3
    loop do
      record = "#{length} ".b + payload
      return record if record.bytesize == length

      length = record.bytesize
    end
  end

  def write_pax_entry(file, path, records)
    contents =
      records.sort_by { |key, _value| key }.map do |key, value|
        pax_record(key, value)
      end.join
    header =
      Gem::Package::TarHeader.new(
        name: "PaxHeaders/#{Digest::SHA256.hexdigest(path)[0, 32]}",
        prefix: "",
        mode: 0o644,
        size: contents.bytesize,
        typeflag: "x",
        mtime: Time.at(0).utc
      ).to_s
    file.write(header)
    file.write(contents)
    file.write("\0" * ((512 - (contents.bytesize % 512)) % 512))
  end

  def tar_entry_name(file, tar, path, records = {})
    archive_name = path
    begin
      tar.send(:split_name, archive_name)
    rescue Gem::Package::TooLongFileName
      records = records.merge("path" => path)
      archive_name = "PaxPaths/#{Digest::SHA256.hexdigest(path)}"
    end
    write_pax_entry(file, path, records) unless records.empty?
    archive_name
  end

  def write_git_archive(checkout, entries, archive)
    previous_epoch = ENV["SOURCE_DATE_EPOCH"]
    ENV["SOURCE_DATE_EPOCH"] = "0"
    File.open(archive, "wb") do |file|
      Gem::Package::TarWriter.new(file) do |tar|
        git_tree_directories(entries).each do |directory|
          tar.mkdir(tar_entry_name(file, tar, directory), 0o755)
        end
        blobs = entries.select { |entry| entry["type"] == "blob" }
        each_git_blob(checkout, blobs) do |entry, contents|
          path = entry.fetch("path")
          case entry.fetch("mode")
          when "100644"
            archive_name = tar_entry_name(file, tar, path)
            tar.add_file_simple(archive_name, 0o644, contents.bytesize) do |io|
              io.write(contents)
            end
          when "100755"
            archive_name = tar_entry_name(file, tar, path)
            tar.add_file_simple(archive_name, 0o755, contents.bytesize) do |io|
              io.write(contents)
            end
          when "120000"
            if contents.include?("\0")
              raise CandidateError, "git tree contains an invalid symlink: #{path}"
            end
            records = {}
            records["linkpath"] = contents if contents.bytesize > 100
            archive_name = tar_entry_name(file, tar, path, records)
            tar.add_symlink(archive_name, contents, 0o777)
          else
            raise CandidateError,
              "git tree contains unsupported mode #{entry.fetch("mode")}: #{path}"
          end
        end
      end
    end
  rescue Gem::Package::TooLongFileName => error
    raise CandidateError, "git tree path cannot be represented safely: #{error.message}"
  ensure
    if previous_epoch.nil?
      ENV.delete("SOURCE_DATE_EPOCH")
    else
      ENV["SOURCE_DATE_EPOCH"] = previous_epoch
    end
  end

  def export_builder(checkout, destination, unit)
    source = unit.fetch("source")
    revision = source.fetch("revision")
    actual_revision = git_output(checkout, "rev-parse", "HEAD").strip
    raise CandidateError, "builder revision mismatch" unless actual_revision == revision

    expected_tree = source["tree"] || source.fetch("sourceTree")
    actual_tree = git_output(checkout, "rev-parse", "#{revision}^{tree}").strip
    raise CandidateError, "builder tree mismatch" unless actual_tree == expected_tree

    destination.mkpath
    repositories =
      export_git_archives(
        checkout,
        revision,
        destination,
        repository_path: "."
      )
    root_repository =
      repositories.find { |repository| repository["repositoryPath"] == "." }
    nested = root_repository.fetch("entries").find do |entry|
      entry["path"] == source.fetch("nestedIshPath")
    end
    unless nested && nested["type"] == "commit" &&
      nested["object"] == source.fetch("nestedIshRevision")
      raise CandidateError, "nested iSH revision is absent from the builder export"
    end
    {
      "repository" => source.fetch("repository"),
      "revision" => revision,
      "tree" => actual_tree,
      "nestedIshPath" => source.fetch("nestedIshPath"),
      "nestedIshRevision" => source.fetch("nestedIshRevision"),
      "repositoryCount" => repositories.length,
      "entryCount" =>
        repositories.sum { |repository| repository.fetch("entries").length },
      "repositories" => repositories
    }
  end

  def export_git_archives(
    checkout,
    revision,
    destination,
    repository_path:
  )
    entries = parse_git_tree(checkout, revision)
    tree = git_output(checkout, "rev-parse", "#{revision}^{tree}").strip
    commit_object = git_output(checkout, "cat-file", "commit", revision)
    archive_relative = "git-source-archives/#{revision}.tar"
    archive = destination.join(archive_relative)
    archive.dirname.mkpath
    write_git_archive(checkout, entries, archive) unless archive.exist?
    repositories = [
      {
        "repositoryPath" => repository_path,
        "revision" => revision,
        "tree" => tree,
        "commitObjectBase64" => Base64.strict_encode64(commit_object),
        "archivePath" => archive_relative,
        "entries" => entries
      }
    ]
    entries.select { |entry| entry["type"] == "commit" }.each do |entry|
      relative = entry.fetch("path")
      submodule = checkout.join(relative)
      if submodule.symlink? || !submodule.directory?
        raise CandidateError, "required git submodule is not initialized: #{relative}"
      end
      actual_revision = git_output(submodule, "rev-parse", "HEAD").strip
      unless actual_revision == entry.fetch("object")
        raise CandidateError,
          "git submodule revision mismatch: " \
          "#{[repository_path, relative].reject { |part| part == "." }.join("/")}"
      end
      nested_path =
        [repository_path, relative].reject { |part| part == "." }.join("/")
      repositories.concat(
        export_git_archives(
          submodule,
          actual_revision,
          destination,
          repository_path: nested_path
        )
      )
    end
    repositories
  end

  def run_verifier(arguments, label)
    command_output(arguments, label)
  end

  def verify_input_bundles(inputs, documents)
    run_verifier(
      [
        RbConfig.ruby,
        repository_root.join("Scripts/prepare-rootfs-source-bundle.rb").to_s,
        "--manifest",
        documents.fetch("SOURCE-ACQUISITION.json").fetch(:path).to_s,
        "--source-inventory",
        documents.fetch("SOURCE-INVENTORY.json").fetch(:path).to_s,
        "--review-results",
        documents.fetch("CORRESPONDING-SOURCE-REVIEW-RESULTS.json").fetch(:path).to_s,
        "--verify",
        inputs.fetch(:source_bundle).to_s
      ],
      "corresponding-source candidate verifier"
    )
    run_verifier(
      [
        RbConfig.ruby,
        repository_root.join("Scripts/prepare-rootfs-license-notice-bundle.rb").to_s,
        "--candidates",
        documents.fetch("LICENSE-NOTICE-CANDIDATES.json").fetch(:path).to_s,
        "--results",
        documents.fetch("LICENSE-REVIEW-RESULTS.json").fetch(:path).to_s,
        "--review-manifest",
        documents.fetch("LICENSE-REVIEW.json").fetch(:path).to_s,
        "--source-manifest",
        documents.fetch("SOURCE-ACQUISITION.json").fetch(:path).to_s,
        "--source-inventory",
        documents.fetch("SOURCE-INVENTORY.json").fetch(:path).to_s,
        "--source-review-results",
        documents.fetch("CORRESPONDING-SOURCE-REVIEW-RESULTS.json").fetch(:path).to_s,
        "--source-bundle",
        inputs.fetch(:source_bundle).to_s,
        "--license-review",
        inputs.fetch(:license_review_bundle).to_s,
        "--verify",
        inputs.fetch(:license_notice_bundle).to_s
      ],
      "LICENSE/NOTICE candidate verifier"
    )
    run_verifier(
      [
        RbConfig.ruby,
        repository_root.join(
          "Scripts/rootfs-license-notice-review-results.rb"
        ).to_s,
        "--bundle",
        inputs.fetch(:license_notice_bundle).to_s,
        documents.fetch(
          "LICENSE-NOTICE-REVIEW-RESULTS.json"
        ).fetch(:path).to_s,
        documents.fetch("LICENSE-NOTICE-CANDIDATES.json").fetch(:path).to_s,
        documents.fetch("LICENSE-REVIEW-RESULTS.json").fetch(:path).to_s,
        documents.fetch("LICENSE-REVIEW.json").fetch(:path).to_s,
        documents.fetch("SOURCE-ACQUISITION.json").fetch(:path).to_s,
        documents.fetch("SOURCE-INVENTORY.json").fetch(:path).to_s
      ],
      "LICENSE/NOTICE review-results verifier"
    )
  end

  def copy_tree(source, destination)
    destination.mkpath
    Find.find(source.to_s) do |entry|
      pathname = Pathname(entry)
      next if pathname == source

      relative = pathname.relative_path_from(source)
      target = destination.join(relative)
      stat = pathname.lstat
      if stat.symlink?
        target.dirname.mkpath
        target.make_symlink(pathname.readlink)
      elsif stat.directory?
        target.mkdir unless target.exist?
        target.chmod(stat.mode & 0o777)
      elsif stat.file?
        target.dirname.mkpath
        FileUtils.copy_file(pathname, target)
        target.chmod(stat.mode & 0o777)
      else
        raise CandidateError, "input tree contains a special node: #{relative}"
      end
    end
  end

  def modifications_markdown(unit)
    rows = unit.fetch("items").map { |item| "- #{item}" }.join("\n")
    <<~MARKDOWN
      # PocketRoot RootFS modification disclosure candidate

      The indexed RootFS build modifies its Alpine and iSH inputs as follows:

      #{rows}

      This engineering disclosure is part of an external delivery candidate.
      It is not a source offer, legal approval, delivery approval, or
      redistribution authorization.
    MARKDOWN
  end

  def tree_entries(root, excluded: [])
    entries = []
    Find.find(root.to_s) do |entry|
      pathname = Pathname(entry)
      next if pathname == root

      relative = pathname.relative_path_from(root).to_s
      next if excluded.include?(relative)

      stat = pathname.lstat
      record = {
        "path" => relative,
        "mode" => format("%04o", stat.mode & 0o777)
      }
      if stat.symlink?
        record["type"] = "symlink"
        record["target"] = pathname.readlink.to_s
      elsif stat.directory?
        record["type"] = "directory"
      elsif stat.file?
        record["type"] = "file"
        record["byteCount"] = stat.size
        record["sha256"] = Digest::SHA256.file(pathname).hexdigest
      else
        raise CandidateError, "candidate contains a special node: #{relative}"
      end
      entries << record
    end
    entries.sort_by { |entry| entry.fetch("path") }
  end

  def checksum_lines(root)
    root.glob("**/*", File::FNM_DOTMATCH)
      .select { |path| path.lstat.file? }
      .map { |path| path.relative_path_from(root).to_s }
      .reject { |relative| relative == "SHA256SUMS" }
      .sort
      .map do |relative|
        "#{Digest::SHA256.file(root.join(relative)).hexdigest}  #{relative}"
      end
  end

  def receipt(documents, source_exports, alpine)
    {
      "schemaVersion" => 1,
      "bundleKind" => "rootfs-delivery-candidate-unapproved",
      "archive" => {
        "version" => ARCHIVE_VERSION,
        "sha256" => ARCHIVE_SHA256
      },
      "inputEvidence" => EVIDENCE_FILES.to_h do |filename|
        [
          filename,
          {"sha256" => sha256(documents.fetch(filename).fetch(:contents))}
        ]
      end,
      "deliveryUnits" => {
        "historicalRootFSBuilderSourceExported" => true,
        "successorRootFSBuilderSourceExported" => true,
        "alpineMinirootfsInputIncluded" => true,
        "correspondingSourceCandidateIncluded" => true,
        "licenseReviewEvidenceIncluded" => true,
        "licenseNoticeCandidateIncluded" => true,
        "modificationDisclosureIncluded" => true
      },
      "gitSourceExportsSha256" => sha256(pretty_json(source_exports)),
      "alpineMinirootfs" => {
        "filename" => alpine.basename.to_s,
        "byteCount" => alpine.size,
        "sha256" => Digest::SHA256.file(alpine).hexdigest
      },
      "candidateInputsVerified" => true,
      "completeCorrespondingSourceBundlePresent" => false,
      "completeLicenseAndNoticeBundlePresent" => false,
      "sourceOfferPrepared" => false,
      "deliveryMechanismApproved" => false,
      "legalReviewApproved" => false,
      "redistributionApproved" => false,
      "distributionAuthorized" => false,
      "status" =>
        "materialized-engineering-delivery-candidate-approval-gates-open"
    }
  end

  def verify_receipt(actual, documents, source_exports, alpine)
    expected = receipt(documents, source_exports, alpine)
    unless actual == expected
      raise CandidateError,
        "delivery candidate receipt does not match the generated receipt schema"
    end
  end

  def materialize(output, inputs, documents, validated)
    inventory = validated.fetch(:inventory)
    units = validated.fetch(:units)
    alpine_unit = units.fetch("alpine-minirootfs-input").fetch("source")
    unless Digest::SHA256.file(inputs.fetch(:alpine_minirootfs)).hexdigest ==
      alpine_unit.fetch("sha256")
      raise CandidateError, "Alpine minirootfs checksum mismatch"
    end

    verify_input_bundles(inputs, documents)
    staging =
      output.parent.join(
        ".#{output.basename}.staging-#{Process.pid}-#{SecureRandom.hex(8)}"
      )
    raise CandidateError, "staging path already exists: #{staging}" if staging.exist?

    begin
      staging.mkdir(0o700)
      source_exports = {
        "schemaVersion" => 1,
        "historicalRootFSBuilder" =>
          export_builder(
            inputs.fetch(:historical_builder),
            staging,
            units.fetch("historical-rootfs-builder")
          ),
        "successorRootFSBuilder" =>
          export_builder(
            inputs.fetch(:successor_builder),
            staging,
            units.fetch("successor-rootfs-builder")
          )
      }
      copy_tree(
        inputs.fetch(:source_bundle),
        staging.join("corresponding-source-candidate")
      )
      copy_tree(
        inputs.fetch(:license_notice_bundle),
        staging.join("license-notice-candidate")
      )
      copy_tree(
        inputs.fetch(:license_review_bundle),
        staging.join("license-review-evidence")
      )
      alpine_destination =
        staging.join("inputs", inputs.fetch(:alpine_minirootfs).basename)
      alpine_destination.dirname.mkpath
      FileUtils.copy_file(inputs.fetch(:alpine_minirootfs), alpine_destination)
      alpine_destination.chmod(0o644)
      evidence = staging.join("evidence")
      evidence.mkpath
      EVIDENCE_FILES.each do |filename|
        evidence.join(filename).binwrite(
          documents.fetch(filename).fetch(:contents)
        )
      end
      staging.join("MODIFICATIONS.md").binwrite(
        modifications_markdown(units.fetch("rootfs-modifications"))
      )
      staging.join("GIT-SOURCE-EXPORTS.json").binwrite(pretty_json(source_exports))
      staging.join("DELIVERY-CANDIDATE-RECEIPT.json").binwrite(
        pretty_json(receipt(documents, source_exports, inputs.fetch(:alpine_minirootfs)))
      )
      manifest = {
        "schemaVersion" => 1,
        "entries" =>
          tree_entries(staging, excluded: %w[TREE-MANIFEST.json SHA256SUMS])
      }
      staging.join("TREE-MANIFEST.json").binwrite(pretty_json(manifest))
      staging.join("SHA256SUMS").binwrite("#{checksum_lines(staging).join("\n")}\n")
      verify_candidate(staging, documents, inventory: inventory)
      File.rename(staging, output)
    ensure
      FileUtils.remove_entry(staging) if staging.exist?
    end
  end

  def require_candidate_file(root, relative)
    unless safe_relative_path?(relative)
      raise CandidateError, "candidate path is unsafe: #{relative}"
    end
    current = root
    relative.split("/").each do |component|
      current = current.join(component)
      if current.symlink?
        raise CandidateError, "candidate file path contains a symlink: #{relative}"
      end
    end
    unless current.exist? && current.lstat.file?
      raise CandidateError, "candidate file is missing: #{relative}"
    end
    current
  end

  def require_candidate_directory(root, relative)
    unless safe_relative_path?(relative)
      raise CandidateError, "candidate path is unsafe: #{relative}"
    end
    current = root
    relative.split("/").each do |component|
      current = current.join(component)
      if current.symlink?
        raise CandidateError,
          "candidate directory path contains a symlink: #{relative}"
      end
    end
    unless current.exist? && current.lstat.directory?
      raise CandidateError, "candidate directory is missing: #{relative}"
    end
    current
  end

  def git_object_digest(contents, object, type: "blob")
    input = "#{type} #{contents.bytesize}\0".b + contents.b
    case object.length
    when 40
      Digest::SHA1.hexdigest(input)
    when 64
      Digest::SHA256.hexdigest(input)
    else
      raise CandidateError, "git source export contains an invalid object id"
    end
  end

  def git_tree_digest(entries, object_length: nil)
    root = GitTreeNode.new({})
    entries.each do |entry|
      components = entry.fetch("path").split("/")
      leaf = components.pop
      node = root
      components.each do |component|
        existing = node.children[component]
        if existing && !existing.is_a?(GitTreeNode)
          raise CandidateError, "git source export has a path/tree collision"
        end
        node.children[component] ||= GitTreeNode.new({})
        node = node.children.fetch(component)
      end
      if node.children.key?(leaf)
        raise CandidateError, "git source export has a duplicate tree entry"
      end
      node.children[leaf] = entry
    end
    git_tree_node_digest(root, object_length: object_length)
  end

  def git_tree_node_digest(node, object_length: nil)
    children = node.children.map do |name, value|
      if value.is_a?(GitTreeNode)
        {
          name: name,
          sort_name: "#{name}/".b,
          mode: "40000",
          object:
            git_tree_node_digest(value, object_length: object_length)
        }
      else
        {
          name: name,
          sort_name: name.b,
          mode: value.fetch("mode"),
          object: value.fetch("object")
        }
      end
    end
    object_lengths = children.map { |child| child.fetch(:object).length }.uniq
    unless object_lengths.length <= 1 && [nil, 40, 64].include?(object_lengths.first)
      raise CandidateError, "git source export mixes incompatible object formats"
    end
    if object_length &&
      (![40, 64].include?(object_length) ||
        (object_lengths.first && object_lengths.first != object_length))
      raise CandidateError, "git source export object format does not match its commit"
    end
    contents = children.sort_by { |child| child.fetch(:sort_name) }.map do |child|
      object = child.fetch(:object)
      "#{child.fetch(:mode)} #{child.fetch(:name)}\0".b +
        [object].pack("H*")
    end.join
    object_length ||= object_lengths.first || 40
    git_object_digest(
      contents,
      "0" * object_length,
      type: "tree"
    )
  end

  def parse_pax_records(contents)
    records = {}
    offset = 0
    while offset < contents.bytesize
      space = contents.index(" ", offset)
      raise CandidateError, "git archive contains malformed PAX metadata" unless space

      length_text = contents.byteslice(offset, space - offset)
      unless length_text.match?(/\A[1-9][0-9]*\z/)
        raise CandidateError, "git archive contains malformed PAX metadata"
      end
      length = Integer(length_text, 10)
      record = contents.byteslice(offset, length)
      unless record && record.bytesize == length && record.end_with?("\n")
        raise CandidateError, "git archive contains truncated PAX metadata"
      end
      payload = record.byteslice(space - offset + 1, length - (space - offset + 2))
      key, value = payload.split("=", 2)
      unless key && value && !key.empty?
        raise CandidateError, "git archive contains malformed PAX metadata"
      end
      records[key] = value
      offset += length
    end
    records
  end

  def verify_tar_stream_structure(archive)
    zero_block = "\0" * 512
    File.open(archive, "rb") do |file|
      loop do
        header_bytes = file.read(512)
        unless header_bytes && header_bytes.bytesize == 512
          raise CandidateError, "git archive has a truncated header"
        end
        if header_bytes == zero_block
          unless file.read(512) == zero_block && file.eof?
            raise CandidateError,
              "git archive does not have a canonical end-of-archive marker"
          end
          return
        end

        header =
          Gem::Package::TarHeader.from(StringIO.new(header_bytes))
        file.seek(header.size, IO::SEEK_CUR)
        padding_size = (512 - (header.size % 512)) % 512
        unless file.read(padding_size) == ("\0" * padding_size)
          raise CandidateError, "git archive contains non-zero entry padding"
        end
      end
    end
  end

  def canonical_tar_header?(header)
    header.uid.zero? &&
      header.gid.zero? &&
      header.mtime.zero? &&
      header.uname == "wheel" &&
      header.gname == "wheel" &&
      header.magic == "ustar" &&
      header.version.zero? &&
      header.devmajor.zero? &&
      header.devminor.zero?
  end

  def verify_git_archive(archive, entries)
    expected = {}
    entries.each do |entry|
      relative = entry.fetch("path")
      relative_bytes = relative.b
      unless safe_relative_path?(relative_bytes) &&
        !expected.key?(relative_bytes)
        raise CandidateError, "git source export contains an unsafe or duplicate path"
      end
      unless %w[blob commit].include?(entry.fetch("type"))
        raise CandidateError, "git source export contains an unsupported entry type"
      end
      valid_mode =
        if entry.fetch("type") == "blob"
          %w[100644 100755 120000].include?(entry.fetch("mode"))
        else
          entry.fetch("mode") == "160000"
        end
      unless valid_mode &&
        entry.fetch("object").match?(
          /\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/
        )
        raise CandidateError, "git source export contains an invalid entry"
      end
      expected[relative_bytes] = entry
    end
    expected_blobs = expected.select { |_path, entry| entry["type"] == "blob" }
    expected_directories = git_tree_directories(entries).map(&:b)
    actual_blobs = {}
    actual_directories = {}
    content_sha256 = {}
    verify_tar_stream_structure(archive)
    File.open(archive, "rb") do |file|
      Gem::Package::TarReader.new(file) do |tar|
        pending_pax = {}
        tar.each do |entry|
          type = entry.header.typeflag
          unless canonical_tar_header?(entry.header)
            raise CandidateError, "git archive contains noncanonical header metadata"
          end
          if type == "g"
            raise CandidateError, "git archive contains unsupported global PAX metadata"
          end
          if type == "x"
            if entry.header.size > 64 * 1_024 ||
              (entry.header.mode & 0o777) != 0o644
              raise CandidateError, "git archive metadata entry exceeds the safety limit"
            end
            pending_pax = parse_pax_records(entry.read)
            next
          end

          raw_name = (pending_pax.delete("path") || entry.full_name).b
          relative = type == "5" ? raw_name.sub(%r{/\z}, "") : raw_name
          unless safe_relative_path?(relative)
            raise CandidateError, "git archive contains an unsafe path"
          end
          if type == "5"
            unless expected_directories.include?(relative) &&
              !actual_directories.key?(relative) &&
              (entry.header.mode & 0o777) == 0o755 &&
              entry.header.size.zero?
              raise CandidateError,
                "git archive contains an unexpected, duplicate, or mis-moded directory"
            end
            actual_directories[relative] = true
            pending_pax = {}
            next
          end

          pinned = expected_blobs[relative]
          unless pinned && !actual_blobs.key?(relative)
            raise CandidateError, "git archive contains an unexpected or duplicate entry"
          end
          mode = pinned.fetch("mode")
          object = pinned.fetch("object")
          contents =
            case type
            when "0", "\0"
              unless %w[100644 100755].include?(mode) &&
                entry.header.size <= MAX_GIT_BLOB_BYTES
                raise CandidateError, "git archive file mode or size is invalid"
              end
              expected_mode = mode == "100755" ? 0o755 : 0o644
              unless (entry.header.mode & 0o777) == expected_mode
                raise CandidateError, "git archive file mode mismatch: #{relative}"
              end
              entry.read || ""
            when "2"
              unless mode == "120000" &&
                (entry.header.mode & 0o777) == 0o777 &&
                entry.header.size.zero?
                raise CandidateError, "git archive symlink mode mismatch: #{relative}"
              end
              pending_pax.delete("linkpath") || entry.header.linkname
            else
              raise CandidateError,
              "git archive contains an unsupported entry type: #{type.inspect}"
            end
          unless contents.is_a?(String)
            raise CandidateError, "git archive entry payload is missing: #{relative}"
          end
          unless object.match?(/\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/) &&
            git_object_digest(contents, object) == object
            raise CandidateError, "git archive object mismatch: #{relative}"
          end
          actual_blobs[relative] = true
          content_sha256[relative] = Digest::SHA256.hexdigest(contents)
          pending_pax = {}
        end
        unless pending_pax.empty?
          raise CandidateError, "git archive contains unbound PAX metadata"
        end
      end
      unless file.read == ("\0" * 512)
        raise CandidateError,
          "git archive does not have a canonical end-of-archive marker"
      end
    end
    unless actual_blobs.keys.sort == expected_blobs.keys.sort
      missing = expected_blobs.keys.sort - actual_blobs.keys.sort
      unexpected = actual_blobs.keys.sort - expected_blobs.keys.sort
      raise CandidateError,
        "git archive path set does not match its manifest: #{archive} " \
        "(missing=#{missing.first.inspect}, unexpected=#{unexpected.first.inspect})"
    end
    unless actual_directories.keys.sort == expected_directories.sort
      raise CandidateError,
        "git archive directory set does not match its manifest: #{archive}"
    end
    content_sha256
  rescue Gem::Package::TarInvalidError => error
    raise CandidateError, "git source archive is invalid: #{error.message}"
  end

  def verify_git_export(root, export, source)
    repositories = export.fetch("repositories")
    unless repositories.is_a?(Array) &&
      export.fetch("repositoryCount") == repositories.length &&
      export.fetch("entryCount") ==
        repositories.sum { |repository| repository.fetch("entries").length }
      raise CandidateError, "git source export has an invalid repository count"
    end
    by_path = {}
    archive_paths = {}
    content_digests = {}
    repositories.each do |repository|
      repository_path = repository.fetch("repositoryPath")
      archive_path = repository.fetch("archivePath")
      revision = repository.fetch("revision")
      valid_repository_path =
        repository_path == "." || safe_relative_path?(repository_path)
      unless valid_repository_path &&
        safe_relative_path?(archive_path) &&
        archive_path == "git-source-archives/#{revision}.tar" &&
        !by_path.key?(repository_path)
        raise CandidateError, "git source export repository path is invalid"
      end
      if archive_paths.key?(archive_path) &&
        archive_paths.fetch(archive_path) != revision
        raise CandidateError, "git source export archive identity is inconsistent"
      end
      by_path[repository_path] = repository
      archive_paths[archive_path] = revision
      commit_object =
        Base64.strict_decode64(repository.fetch("commitObjectBase64"))
      unless revision.match?(/\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/) &&
        git_object_digest(commit_object, revision, type: "commit") == revision
        raise CandidateError, "git source export commit object mismatch"
      end
      commit_tree = commit_object.match(
        /\Atree ([0-9a-f]{40}(?:[0-9a-f]{24})?)\n/
      )&.captures&.first
      calculated_tree =
        git_tree_digest(
          repository.fetch("entries"),
          object_length: revision.length
        )
      unless commit_tree &&
        repository.fetch("tree") == commit_tree &&
        calculated_tree == commit_tree
        raise CandidateError, "git source export commit/tree binding mismatch"
      end
      archive = require_candidate_file(root, archive_path)
      content_digests[repository_path] =
        verify_git_archive(archive, repository.fetch("entries"))
    end
    root_repository = by_path.fetch(".")
    unless root_repository.fetch("revision") == export.fetch("revision") &&
      root_repository.fetch("tree") == export.fetch("tree") &&
      export.fetch("tree") == (source["tree"] || source.fetch("sourceTree"))
      raise CandidateError, "git source root archive binding mismatch"
    end
    if source.key?("nestedIshPath") || source.key?("nestedIshRevision")
      nested = root_repository.fetch("entries").find do |entry|
        entry["path"] == source.fetch("nestedIshPath")
      end
      unless nested &&
        nested["type"] == "commit" &&
        nested["object"] == source.fetch("nestedIshRevision")
        raise CandidateError,
          "declared nested iSH gitlink is absent from the root tree"
      end
    end
    reachable_paths = { "." => true }
    repositories.each do |repository|
      parent_path = repository.fetch("repositoryPath")
      repository.fetch("entries")
        .select { |entry| entry["type"] == "commit" }
        .each do |entry|
          child_path =
            [parent_path, entry.fetch("path")]
              .reject { |component| component == "." }
              .join("/")
          child = by_path[child_path]
          unless child && child.fetch("revision") == entry.fetch("object")
            raise CandidateError, "git submodule archive binding mismatch: #{child_path}"
          end
          reachable_paths[child_path] = true
        end
    end
    unless reachable_paths.keys.sort == by_path.keys.sort
      raise CandidateError, "git source export contains an unreachable repository"
    end
    {
      "buildScriptPath" => "buildScriptSHA256",
      "candidateScriptPath" => "candidateScriptSHA256",
      "captureScriptPath" => "captureScriptSHA256",
      "rootfsPinPath" => "rootfsPinSHA256"
    }.each do |path_key, digest_key|
      next unless source.key?(path_key)

      relative = source.fetch(path_key)
      unless content_digests.fetch(".")[relative.b] == source.fetch(digest_key)
        raise CandidateError, "builder script checksum mismatch: #{relative}"
      end
    end
  rescue ArgumentError, KeyError, TypeError => error
    raise CandidateError, "git source export is invalid: #{error.message}"
  end

  def verify_modification_disclosure(root, unit)
    disclosure = require_candidate_file(root, "MODIFICATIONS.md")
    unless disclosure.binread == modifications_markdown(unit)
      raise CandidateError,
        "delivery candidate modification disclosure does not match its index"
    end
  end

  def verify_builder_inventory_binding(export, source, key)
    {
      "repository" => "repository",
      "revision" => "revision",
      "nestedIshPath" => "nestedIshPath",
      "nestedIshRevision" => "nestedIshRevision"
    }.each do |export_key, source_key|
      unless export.fetch(export_key) == source.fetch(source_key)
        raise CandidateError,
          "git source export inventory binding mismatch: #{key}/#{export_key}"
      end
    end
  end

  def immediate_path_types(root)
    root.children.sort_by { |path| path.basename.to_s }.to_h do |path|
      stat = path.lstat
      type =
        if stat.symlink?
          "symlink"
        elsif stat.directory?
          "directory"
        elsif stat.file?
          "file"
        else
          "special"
        end
      [path.basename.to_s, type]
    end
  end

  def verify_candidate_layout(root, source_exports, alpine_filename)
    expected_root = {
      "DELIVERY-CANDIDATE-RECEIPT.json" => "file",
      "GIT-SOURCE-EXPORTS.json" => "file",
      "MODIFICATIONS.md" => "file",
      "SHA256SUMS" => "file",
      "TREE-MANIFEST.json" => "file",
      "corresponding-source-candidate" => "directory",
      "evidence" => "directory",
      "git-source-archives" => "directory",
      "inputs" => "directory",
      "license-notice-candidate" => "directory",
      "license-review-evidence" => "directory"
    }
    expected_evidence = EVIDENCE_FILES.to_h { |filename| [filename, "file"] }
    expected_archives =
      source_exports
        .values_at("historicalRootFSBuilder", "successorRootFSBuilder")
        .flat_map { |export| export.fetch("repositories") }
        .map { |repository| Pathname(repository.fetch("archivePath")).basename.to_s }
        .uniq
        .to_h { |filename| [filename, "file"] }
    expected_inputs = {alpine_filename => "file"}
    checks = [
      [root, expected_root],
      [require_candidate_directory(root, "evidence"), expected_evidence],
      [
        require_candidate_directory(root, "git-source-archives"),
        expected_archives
      ],
      [require_candidate_directory(root, "inputs"), expected_inputs]
    ]
    checks.each do |directory, expected|
      unless immediate_path_types(directory) == expected.sort.to_h
        raise CandidateError,
          "delivery candidate path/type set contains missing or unreviewed content: " \
          "#{directory.relative_path_from(root)}"
      end
    end
  rescue KeyError, TypeError => error
    raise CandidateError, "delivery candidate layout is invalid: #{error.message}"
  end

  def verify_candidate(root, documents, inventory: nil)
    root = Pathname(root)
    if root.symlink? || !root.directory?
      raise CandidateError, "delivery candidate is not a real directory"
    end
    root = root.realpath
    if within_path?(root, repository_root)
      raise CandidateError, "delivery candidate must be outside the repository"
    end
    receipt_path = require_candidate_file(root, "DELIVERY-CANDIDATE-RECEIPT.json")
    receipt = JSON.parse(receipt_path.binread)
    validate_archive(receipt, "delivery candidate receipt")
    unless receipt.fetch("schemaVersion") == 1 &&
      receipt.fetch("bundleKind") == "rootfs-delivery-candidate-unapproved" &&
      receipt.fetch("candidateInputsVerified") == true
      raise CandidateError, "delivery candidate receipt has an invalid schema"
    end
    %w[
      completeCorrespondingSourceBundlePresent
      completeLicenseAndNoticeBundlePresent
      sourceOfferPrepared
      deliveryMechanismApproved
      legalReviewApproved
      redistributionApproved
      distributionAuthorized
    ].each do |gate|
      unless receipt[gate] == false
        raise CandidateError, "delivery candidate authorization gate is open: #{gate}"
      end
    end
    EVIDENCE_FILES.each do |filename|
      expected_bytes = documents.fetch(filename).fetch(:contents)
      bundled = require_candidate_file(root, "evidence/#{filename}")
      expected_digest = sha256(expected_bytes)
      unless bundled.binread == expected_bytes &&
        receipt.fetch("inputEvidence").fetch(filename).fetch("sha256") ==
          expected_digest
        raise CandidateError, "delivery candidate evidence drift: #{filename}"
      end
    end
    source_exports_path = require_candidate_file(root, "GIT-SOURCE-EXPORTS.json")
    unless sha256(source_exports_path.binread) ==
      receipt.fetch("gitSourceExportsSha256")
      raise CandidateError, "git source export receipt binding mismatch"
    end
    source_exports = JSON.parse(source_exports_path.binread)
    unless source_exports.fetch("schemaVersion") == 1
      raise CandidateError, "git source export manifest schema is unsupported"
    end
    units =
      (inventory || documents.fetch("SOURCE-DELIVERY-INVENTORY.json").fetch(:document))
        .fetch("deliveryUnits")
        .to_h { |unit| [unit.fetch("id"), unit] }
    {
      "historicalRootFSBuilder" => "historical-rootfs-builder",
      "successorRootFSBuilder" => "successor-rootfs-builder"
    }.each do |key, unit_id|
      export = source_exports.fetch(key)
      source = units.fetch(unit_id).fetch("source")
      verify_builder_inventory_binding(export, source, key)
      verify_git_export(root, export, source)
    end
    require_candidate_directory(root, "corresponding-source-candidate")
    require_candidate_directory(root, "license-notice-candidate")
    require_candidate_directory(root, "license-review-evidence")
    verify_modification_disclosure(root, units.fetch("rootfs-modifications"))
    alpine_source = units.fetch("alpine-minirootfs-input").fetch("source")
    alpine_receipt = receipt.fetch("alpineMinirootfs")
    alpine = require_candidate_file(
      root,
      "inputs/#{alpine_receipt.fetch("filename")}"
    )
    unless Digest::SHA256.file(alpine).hexdigest == alpine_source.fetch("sha256") &&
      alpine_receipt.fetch("sha256") == alpine_source.fetch("sha256") &&
      alpine_receipt.fetch("byteCount") == alpine.size
      raise CandidateError, "delivery candidate Alpine input mismatch"
    end
    verify_receipt(receipt, documents, source_exports, alpine)
    verify_candidate_layout(root, source_exports, alpine.basename.to_s)

    manifest_path = require_candidate_file(root, "TREE-MANIFEST.json")
    manifest = JSON.parse(manifest_path.binread)
    unless manifest.fetch("schemaVersion") == 1 &&
      manifest.fetch("entries") ==
        tree_entries(root, excluded: %w[TREE-MANIFEST.json SHA256SUMS])
      raise CandidateError, "delivery candidate tree does not match TREE-MANIFEST.json"
    end
    checksum_path = require_candidate_file(root, "SHA256SUMS")
    expected_lines = checksum_lines(root)
    unless checksum_path.binread == "#{expected_lines.join("\n")}\n"
      raise CandidateError, "delivery candidate checksums do not match SHA256SUMS"
    end
    verify_input_bundles(
      {
        source_bundle: root.join("corresponding-source-candidate"),
        license_notice_bundle: root.join("license-notice-candidate"),
        license_review_bundle: root.join("license-review-evidence")
      },
      documents
    )
    true
  rescue JSON::ParserError, KeyError, TypeError => error
    raise CandidateError, "delivery candidate is invalid: #{error.message}"
  end

  def execute(arguments)
    options = parse_options(arguments)
    if options[:verify]
      root = resolve_external_directory(options.fetch(:verify), "--verify")
      canonical_documents = load_documents(options)
      candidate_documents = load_candidate_documents(root)
      verify_canonical_evidence(candidate_documents, canonical_documents)
      validated = validate_documents(canonical_documents)
      verify_candidate(
        root,
        canonical_documents,
        inventory: validated.fetch(:inventory)
      )
      puts "Verified unapproved RootFS delivery candidate at #{root}."
      return
    end

    documents = load_documents(options)
    validated = validate_documents(documents)
    if options.fetch(:validate_only)
      puts "RootFS delivery-candidate inputs are valid " \
        "(#{validated.fetch(:units).length} indexed delivery units; " \
        "all approval gates closed)."
      return
    end
    inputs = {
      historical_builder:
        resolve_external_directory(
          options.fetch(:historical_builder),
          "--historical-builder"
        ),
      successor_builder:
        resolve_external_directory(
          options.fetch(:successor_builder),
          "--successor-builder"
        ),
      alpine_minirootfs:
        resolve_external_file(
          options.fetch(:alpine_minirootfs),
          "--alpine-minirootfs"
        ),
      source_bundle:
        resolve_external_directory(options.fetch(:source_bundle), "--source-bundle"),
      license_notice_bundle:
        resolve_external_directory(
          options.fetch(:license_notice_bundle),
          "--license-notice-bundle"
        ),
      license_review_bundle:
        resolve_external_directory(
          options.fetch(:license_review_bundle),
          "--license-review-bundle"
        )
    }
    output = validate_new_output(options.fetch(:output), inputs.values)
    materialize(output, inputs, documents, validated)
    puts "Materialized unapproved RootFS delivery candidate at #{output}."
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    RootFSDeliveryCandidate.execute(ARGV)
  rescue RootFSDeliveryCandidate::CandidateError,
    OptionParser::ParseError, SystemCallError => error
    warn error.message
    exit 1
  end
end
