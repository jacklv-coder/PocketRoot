#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "find"
require "json"
require "net/http"
require "open3"
require "openssl"
require "optparse"
require "pathname"
require "rbconfig"
require "securerandom"
require "uri"
require_relative "rootfs-corresponding-source-review-results"
require_relative "rootfs-license-notice-candidates"

module RootFSLicenseNoticeBundle
  MAX_LOCAL_PAYLOAD_BYTES = 8 * 1_024 * 1_024
  MAX_COMMAND_OUTPUT_BYTES = 64 * 1_024
  MAX_REDIRECTS = 3
  OPEN_TIMEOUT_SECONDS = 15
  READ_TIMEOUT_SECONDS = 30

  class BundleError < StandardError
  end

  module_function

  def parse_options(arguments)
    options = {
      candidates:
        "Compliance/RootFS/v0.3.3/LICENSE-NOTICE-CANDIDATES.json",
      results:
        "Compliance/RootFS/v0.3.3/LICENSE-REVIEW-RESULTS.json",
      review: "Compliance/RootFS/v0.3.3/LICENSE-REVIEW.json",
      source_acquisition:
        "Compliance/RootFS/v0.3.3/SOURCE-ACQUISITION.json",
      source_inventory:
        "Compliance/RootFS/v0.3.3/SOURCE-INVENTORY.json",
      source_review_results:
        "Compliance/RootFS/v0.3.3/CORRESPONDING-SOURCE-REVIEW-RESULTS.json",
      validate_only: false
    }
    parser = OptionParser.new do |commands|
      commands.banner =
        "Usage: ruby Scripts/prepare-rootfs-license-notice-bundle.rb [options]"
      commands.on("--candidates PATH", "Candidate bundle manifest") do |value|
        options[:candidates] = value
      end
      commands.on("--results PATH", "Engineering review results") do |value|
        options[:results] = value
      end
      commands.on("--review-manifest PATH", "License-review manifest") do |value|
        options[:review] = value
      end
      commands.on("--source-manifest PATH", "Source-acquisition manifest") do |value|
        options[:source_acquisition] = value
      end
      commands.on("--source-inventory PATH", "Generated source inventory") do |value|
        options[:source_inventory] = value
      end
      commands.on(
        "--source-review-results PATH",
        "Pinned corresponding-source candidate review results"
      ) do |value|
        options[:source_review_results] = value
      end
      commands.on("--source-bundle DIR", "Verified external source bundle") do |value|
        options[:source_bundle] = value
      end
      commands.on("--license-review DIR", "Verified external license review") do |value|
        options[:license_review] = value
      end
      commands.on("--download-cache DIR", "Optional pinned remote payload cache") do |value|
        options[:download_cache] = value
      end
      commands.on("--output DIR", "New external candidate bundle directory") do |value|
        options[:output] = value
      end
      commands.on("--verify DIR", "Verify an external candidate bundle") do |value|
        options[:verify] = value
      end
      commands.on("--validate-only", "Validate manifests without payloads") do
        options[:validate_only] = true
      end
    end
    parser.parse!(arguments)
    unless arguments.empty?
      raise OptionParser::InvalidOption, arguments.join(" ")
    end

    modes = [
      options.fetch(:validate_only),
      !options[:output].nil?,
      !options[:verify].nil?
    ].count(true)
    unless modes == 1
      raise OptionParser::InvalidOption,
        "select exactly one of --validate-only, --output, or --verify"
    end
    unless options.fetch(:validate_only)
      raise OptionParser::MissingArgument, "--source-bundle" unless options[:source_bundle]
      raise OptionParser::MissingArgument, "--license-review" unless options[:license_review]
    end

    options
  end

  def repository_root
    Pathname(__dir__).parent.realpath
  end

  def within_path?(candidate, parent)
    candidate == parent ||
      candidate.to_s.start_with?("#{parent}#{File::SEPARATOR}")
  end

  def resolve_external_directory(value, label)
    directory = Pathname(value)
    raise BundleError, "#{label} must be absolute" unless directory.absolute?
    raise BundleError, "#{label} must not be a symlink" if directory.symlink?
    raise BundleError, "#{label} is not a directory" unless directory.directory?

    resolved = directory.realpath
    if within_path?(resolved, repository_root)
      raise BundleError, "#{label} must be outside the repository"
    end
    resolved
  end

  def validate_new_output(value, inputs)
    output = Pathname(value)
    raise BundleError, "--output must be absolute" unless output.absolute?
    if output.exist? || output.symlink?
      raise BundleError, "--output already exists: #{output}"
    end
    unless output.parent.directory? && !output.parent.symlink?
      raise BundleError, "--output parent must be a real directory"
    end

    resolved = output.parent.realpath.join(output.basename)
    if within_path?(resolved, repository_root)
      raise BundleError, "--output must be outside the repository"
    end
    inputs.each do |input|
      if within_path?(resolved, input) || within_path?(input, resolved)
        raise BundleError, "--output must not overlap an input directory"
      end
    end
    resolved
  end

  def require_regular_file(root, relative, label, maximum_bytes)
    unless RootFSLicenseNoticeCandidates.safe_relative_path?(relative)
      raise BundleError, "#{label} has an unsafe path"
    end

    current = root
    relative.split("/").each do |component|
      current = current.join(component)
      raise BundleError, "#{label} must not contain a symlink" if current.symlink?
    end
    unless current.exist? && current.lstat.file?
      raise BundleError, "#{label} is not a regular file"
    end
    if current.size > maximum_bytes
      raise BundleError, "#{label} exceeds #{maximum_bytes} bytes"
    end
    current
  end

  def read_regular_file(root, relative, label, maximum_bytes)
    require_regular_file(root, relative, label, maximum_bytes).binread
  end

  def load_document(path, label)
    pathname = Pathname(path)
    raise BundleError, "#{label} is not a regular file: #{path}" unless pathname.file?

    contents = pathname.binread
    {
      path: pathname,
      contents: contents,
      document: JSON.parse(contents)
    }
  rescue JSON::ParserError => error
    raise BundleError, "#{label} is invalid JSON: #{error.message}"
  end

  def validate_documents(options)
    candidates = load_document(options.fetch(:candidates), "candidate manifest")
    results = load_document(options.fetch(:results), "review results")
    review = load_document(options.fetch(:review), "review manifest")
    source =
      load_document(
        options.fetch(:source_acquisition),
        "source-acquisition manifest"
      )
    inventory =
      load_document(options.fetch(:source_inventory), "source inventory")
    source_review_results =
      load_document(
        options.fetch(:source_review_results),
        "corresponding-source review results"
      )
    allow_file_urls =
      ENV["POCKETROOT_TEST_ALLOW_FILE_URLS"] == "1" &&
      source.fetch(:document)["testFixture"] == true
    validated = RootFSLicenseNoticeCandidates.validate_manifest(
      candidates.fetch(:document),
      results.fetch(:document),
      license_review: review.fetch(:document),
      source_acquisition: source.fetch(:document),
      source_inventory: inventory.fetch(:document),
      results_bytes: results.fetch(:contents),
      license_review_bytes: review.fetch(:contents),
      source_acquisition_bytes: source.fetch(:contents),
      allow_file_urls: allow_file_urls
    )
    begin
      RootFSCorrespondingSourceReviewResults.validate_manifest(
        source_review_results.fetch(:document),
        source.fetch(:document),
        inventory.fetch(:document),
        source_acquisition_bytes: source.fetch(:contents),
        allow_file_urls: allow_file_urls
      )
    rescue RootFSCorrespondingSourceReviewResults::ValidationError => error
      raise BundleError,
        "corresponding-source review results are invalid: #{error.message}"
    end
    {
      candidates: candidates,
      results: results,
      review: review,
      source: source,
      inventory: inventory,
      source_review_results: source_review_results,
      validated: validated,
      allow_file_urls: allow_file_urls
    }
  rescue RootFSLicenseNoticeCandidates::ValidationError => error
    raise BundleError, error.message
  end

  def run_verifier(command, label)
    output = +"".b
    output_lock = Mutex.new
    truncated = false
    status = nil
    Open3.popen3(*command) do |stdin, stdout, stderr, wait_thread|
      stdin.close
      readers = [stdout, stderr].map do |stream|
        Thread.new do
          loop do
            chunk = stream.readpartial(16 * 1_024)
            output_lock.synchronize do
              remaining = MAX_COMMAND_OUTPUT_BYTES - output.bytesize
              if remaining.positive?
                output << chunk.byteslice(0, remaining)
              end
              truncated = true if chunk.bytesize > remaining
            end
          end
        rescue EOFError
          nil
        end
      end
      readers.each(&:join)
      status = wait_thread.value
    end
    output << "\n[output truncated]\n" if truncated
    return if status.success?

    raise BundleError,
      "#{label} failed (exit #{status.exitstatus}):\n#{output}"
  end

  def verify_inputs(source_bundle, license_review, documents)
    source_command = [
      RbConfig.ruby,
      repository_root.join("Scripts/prepare-rootfs-source-bundle.rb").to_s,
      "--manifest",
      documents.fetch(:source).fetch(:path).to_s,
      "--source-inventory",
      documents.fetch(:inventory).fetch(:path).to_s,
      "--review-results",
      documents.fetch(:source_review_results).fetch(:path).to_s,
      "--verify",
      source_bundle.to_s
    ]
    run_verifier(source_command, "source bundle verification")

    review_command = [
      RbConfig.ruby,
      repository_root.join("Scripts/prepare-rootfs-license-review.rb").to_s,
      "--review-manifest",
      documents.fetch(:review).fetch(:path).to_s,
      "--source-manifest",
      documents.fetch(:source).fetch(:path).to_s,
      "--source-inventory",
      documents.fetch(:inventory).fetch(:path).to_s,
      "--source-review-results",
      documents.fetch(:source_review_results).fetch(:path).to_s,
      "--source-bundle",
      source_bundle.to_s,
      "--verify",
      license_review.to_s
    ]
    run_verifier(review_command, "license review verification")
  end

  def verify_payload_bytes(contents, payload, label)
    unless contents.bytesize == payload.fetch("byteCount")
      raise BundleError,
        "#{label} byte count mismatch: expected " \
        "#{payload.fetch("byteCount")}, got #{contents.bytesize}"
    end
    digest = Digest::SHA256.hexdigest(contents)
    unless digest == payload.fetch("sha256")
      raise BundleError,
        "#{label} SHA-256 mismatch: expected #{payload.fetch("sha256")}, got #{digest}"
    end
    contents
  end

  def verify_sha256(contents, expected, label)
    digest = Digest::SHA256.hexdigest(contents)
    unless digest == expected
      raise BundleError,
        "#{label} SHA-256 mismatch: expected #{expected}, got #{digest}"
    end
    contents
  end

  def source_tree_file_digests(source_bundle, expected_paths)
    contents =
      read_regular_file(
        source_bundle,
        "TREE-MANIFEST.json",
        "source bundle tree manifest",
        MAX_LOCAL_PAYLOAD_BYTES
      )
    document = JSON.parse(contents)
    entries = document["entries"]
    unless document["schemaVersion"] == 1 && entries.is_a?(Array)
      raise BundleError, "source bundle tree manifest is invalid"
    end
    file_digests = {}
    entries.each do |entry|
      next unless entry.is_a?(Hash) && entry["type"] == "file"

      path = entry["path"]
      digest = entry["sha256"]
      unless path.is_a?(String) &&
        !path.empty? &&
        digest.is_a?(String) &&
        digest.match?(RootFSLicenseNoticeCandidates::SHA256_PATTERN) &&
        !file_digests.key?(path)
        raise BundleError, "source bundle tree manifest has invalid file entries"
      end
      file_digests[path] = digest
    end
    unless expected_paths.all? { |path| file_digests.key?(path) }
      raise BundleError,
        "source bundle tree manifest does not cover candidate aports files"
    end
    file_digests
  rescue JSON::ParserError => error
    raise BundleError,
      "source bundle tree manifest is invalid JSON: #{error.message}"
  end

  def read_cached_payload(cache, payload)
    read_regular_file(
      cache,
      payload.fetch("cacheKey"),
      "cached remote payload #{payload.fetch("cacheKey")}",
      RootFSLicenseNoticeCandidates::MAX_REMOTE_PAYLOAD_BYTES
    )
  end

  def download_https(url, maximum_bytes, redirects = MAX_REDIRECTS)
    raise BundleError, "too many redirects while downloading #{url}" if redirects.negative?

    uri = URI.parse(url)
    unless uri.is_a?(URI::HTTPS) && !uri.host.to_s.empty? &&
      uri.userinfo.nil? && uri.fragment.nil?
      raise BundleError, "remote payload URL is not safe HTTPS: #{url}"
    end
    request = Net::HTTP::Get.new(uri.request_uri)
    result = nil
    Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: true,
      open_timeout: OPEN_TIMEOUT_SECONDS,
      read_timeout: READ_TIMEOUT_SECONDS
    ) do |http|
      http.request(request) do |response|
        result =
          case response
          when Net::HTTPSuccess
            content_length = response["content-length"]
            if content_length && Integer(content_length, 10) > maximum_bytes
              raise BundleError,
                "remote payload exceeds #{maximum_bytes} bytes: #{url}"
            end
            contents = +"".b
            response.read_body do |chunk|
              contents << chunk
              if contents.bytesize > maximum_bytes
                raise BundleError,
                  "remote payload exceeds #{maximum_bytes} bytes: #{url}"
              end
            end
            [:success, contents]
          when Net::HTTPRedirection
            [:redirect, response["location"]]
          else
            [:failure, response.code]
          end
      end
    end
    unless result
      raise BundleError, "remote payload request returned no response: #{url}"
    end
    case result.fetch(0)
    when :success
      result.fetch(1)
    when :redirect
      location = result.fetch(1)
      raise BundleError, "remote payload redirect has no location: #{url}" unless location

      download_https(URI.join(uri, location).to_s, maximum_bytes, redirects - 1)
    else
      raise BundleError,
        "remote payload request failed with HTTP #{result.fetch(1)}: #{url}"
    end
  rescue ArgumentError, URI::InvalidURIError, Net::ProtocolError, SocketError,
    SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => error
    raise BundleError, "remote payload request failed for #{url}: #{error.message}"
  end

  def read_file_url(url, maximum_bytes)
    uri = URI.parse(url)
    pathname = Pathname(URI.decode_www_form_component(uri.path))
    unless pathname.absolute? && pathname.file? && !pathname.symlink?
      raise BundleError, "fixture payload is not a regular absolute file: #{url}"
    end
    if pathname.size > maximum_bytes
      raise BundleError, "fixture payload exceeds #{maximum_bytes} bytes: #{url}"
    end
    pathname.binread
  end

  def fetch_remote_payload(payload, cache, allow_file_urls)
    if cache
      return verify_payload_bytes(
        read_cached_payload(cache, payload),
        payload,
        "cached remote payload #{payload.fetch("cacheKey")}"
      )
    end

    failures = []
    payload.fetch("retrievalURLs").each do |url|
      begin
        contents =
          if allow_file_urls && URI.parse(url).scheme == "file"
            read_file_url(
              url,
              RootFSLicenseNoticeCandidates::MAX_REMOTE_PAYLOAD_BYTES
            )
          else
            download_https(
              url,
              RootFSLicenseNoticeCandidates::MAX_REMOTE_PAYLOAD_BYTES
            )
          end
        return verify_payload_bytes(
          contents,
          payload,
          "remote payload #{payload.fetch("cacheKey")}"
        )
      rescue BundleError => error
        failures << error.message
      end
    end

    raise BundleError,
      "all retrieval URLs failed for #{payload.fetch("cacheKey")}:\n- " \
      "#{failures.join("\n- ")}"
  end

  def pretty_json(value)
    "#{JSON.pretty_generate(value)}\n"
  end

  def notice_markdown(sources, counts)
    rows = sources.map do |source|
      origin = source.fetch("sourceOrigin")
      expressions = source.fetch("declaredLicenseExpressions").join(", ")
      open_items =
        source.fetch("remainingReviewItems")
          .map { |item| "`#{item}`" }
          .join("<br>")
      "| `#{origin}` | #{expressions} | #{open_items} |"
    end

    <<~MARKDOWN
      # RootFS v0.3.3 LICENSE/NOTICE candidate bundle

      This external directory collects checksum-verified engineering candidates
      for the eight source origins that still have open license or attribution
      review items. It contains #{counts.fetch(:existing)} previously reviewed
      evidence files, #{counts.fetch(:remote)} pinned remote reference files,
      and #{counts.fetch(:aports)} aports patch/helper files.

      > This is not a legal NOTICE, redistribution approval, or a complete
      > corresponding-source delivery. Generic SPDX texts—especially the MIT
      > reference with placeholders—do not replace package-specific grants,
      > copyright notices, or legal review.

      | Source origin | Declared expressions | Review items still open |
      | --- | --- | --- |
      #{rows.join("\n")}

      `LICENSE-NOTICE-CANDIDATES.json` records the source and checksum of every
      remote payload. `LICENSE-REVIEW-RESULTS.json` and `LICENSE-REVIEW.json`
      preserve the reviewed evidence chain. `BUNDLE-RECEIPT.json` records the
      manifest bindings and payload counts. `SHA256SUMS` covers every other file
      in this directory.
    MARKDOWN
  end

  def receipt(documents, counts)
    {
      "schemaVersion" => 1,
      "archive" => {
        "version" => RootFSLicenseNoticeCandidates::ARCHIVE_VERSION,
        "sha256" => RootFSLicenseNoticeCandidates::ARCHIVE_SHA256
      },
      "candidateManifestSha256" =>
        Digest::SHA256.hexdigest(
          documents.fetch(:candidates).fetch(:contents)
        ),
      "licenseReviewResultsSha256" =>
        Digest::SHA256.hexdigest(documents.fetch(:results).fetch(:contents)),
      "licenseReviewManifestSha256" =>
        Digest::SHA256.hexdigest(documents.fetch(:review).fetch(:contents)),
      "sourceAcquisitionManifestSha256" =>
        Digest::SHA256.hexdigest(documents.fetch(:source).fetch(:contents)),
      "counts" => {
        "openSourceOrigins" => counts.fetch(:origins),
        "existingEvidenceFiles" => counts.fetch(:existing),
        "remotePayloadFiles" => counts.fetch(:remote),
        "supplementalAportsFiles" => counts.fetch(:aports),
        "candidatePayloadFiles" =>
          counts.fetch(:existing) +
            counts.fetch(:remote) +
            counts.fetch(:aports)
      },
      "status" =>
        RootFSLicenseNoticeCandidates::STATUS,
      "engineeringReviewApproved" => false,
      "legalReviewApproved" => false,
      "redistributionApproved" => false
    }
  end

  def build_payloads(
    source_bundle,
    license_review,
    documents,
    remote_contents
  )
    validated = documents.fetch(:validated)
    payloads = {
      "LICENSE-NOTICE-CANDIDATES.json" =>
        documents.fetch(:candidates).fetch(:contents),
      "LICENSE-REVIEW-RESULTS.json" =>
        documents.fetch(:results).fetch(:contents),
      "LICENSE-REVIEW.json" =>
        documents.fetch(:review).fetch(:contents)
    }
    existing_evidence = validated.fetch(:existing_evidence)
    validated.fetch(:existing_evidence_paths).each do |relative|
      expected = existing_evidence.fetch(relative)
      contents =
        read_regular_file(
          license_review,
          relative,
          "review evidence #{relative}",
          MAX_LOCAL_PAYLOAD_BYTES
        )
      payloads[relative] =
        verify_payload_bytes(
          contents,
          expected,
          "review evidence #{relative}"
        )
    end
    source_digests =
      source_tree_file_digests(
        source_bundle,
        validated.fetch(:aports_paths)
      )
    validated.fetch(:aports_paths).each do |relative|
      contents =
        read_regular_file(
          source_bundle,
          relative,
          "source candidate #{relative}",
          MAX_LOCAL_PAYLOAD_BYTES
        )
      payloads["supplemental/#{relative}"] =
        verify_sha256(
          contents,
          source_digests.fetch(relative),
          "source candidate #{relative}"
        )
    end
    validated.fetch(:remote_payloads).each do |payload|
      payloads[payload.fetch("outputPath")] =
        remote_contents.fetch(payload.fetch("outputPath"))
    end

    counts = {
      origins: validated.fetch(:sources).length,
      existing: validated.fetch(:existing_evidence_paths).length,
      remote: validated.fetch(:remote_payloads).length,
      aports: validated.fetch(:aports_paths).length
    }
    payloads["NOTICE-CANDIDATES.md"] =
      notice_markdown(validated.fetch(:sources), counts)
    payloads["BUNDLE-RECEIPT.json"] = pretty_json(receipt(documents, counts))
    checksum_lines = payloads.sort.map do |relative, contents|
      "#{Digest::SHA256.hexdigest(contents)}  #{relative}"
    end
    payloads["SHA256SUMS"] = "#{checksum_lines.join("\n")}\n"
    payloads
  end

  def remote_contents_for_output(documents, cache)
    documents.fetch(:validated).fetch(:remote_payloads).to_h do |payload|
      [
        payload.fetch("outputPath"),
        fetch_remote_payload(
          payload,
          cache,
          documents.fetch(:allow_file_urls)
        )
      ]
    end
  end

  def remote_contents_from_bundle(bundle, documents)
    documents.fetch(:validated).fetch(:remote_payloads).to_h do |payload|
      relative = payload.fetch("outputPath")
      contents =
        read_regular_file(
          bundle,
          relative,
          "bundle remote payload #{relative}",
          RootFSLicenseNoticeCandidates::MAX_REMOTE_PAYLOAD_BYTES
        )
      [
        relative,
        verify_payload_bytes(contents, payload, "bundle remote payload #{relative}")
      ]
    end
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

  def actual_path_types(root)
    path_types = {}
    Find.find(root.to_s) do |entry|
      pathname = Pathname(entry)
      next if pathname == root

      relative = pathname.relative_path_from(root).to_s
      stat = pathname.lstat
      if stat.symlink?
        raise BundleError, "candidate bundle contains a symlink: #{relative}"
      elsif stat.directory?
        path_types[relative] = "directory"
      elsif stat.file?
        path_types[relative] = "file"
      else
        raise BundleError, "candidate bundle contains a special node: #{relative}"
      end
    end
    path_types.sort.to_h
  end

  def verify_bundle(bundle, expected)
    unless actual_path_types(bundle) == expected_path_types(expected.keys)
      raise BundleError,
        "candidate bundle path/type set does not match expected payloads"
    end
    expected.each do |relative, contents|
      pathname = require_regular_file(
        bundle,
        relative,
        "candidate bundle file #{relative}",
        [MAX_LOCAL_PAYLOAD_BYTES, contents.bytesize].max
      )
      unless pathname.size == contents.bytesize &&
        Digest::SHA256.file(pathname).hexdigest ==
          Digest::SHA256.hexdigest(contents)
        raise BundleError,
          "candidate bundle file does not match expected bytes: #{relative}"
      end
    end
  end

  def materialize(output, payloads)
    staging =
      output.parent.join(
        ".#{output.basename}.staging-#{SecureRandom.hex(8)}"
      )
    begin
      staging.mkdir(0o700)
      payloads.each do |relative, contents|
        destination = staging.join(relative)
        FileUtils.mkdir_p(destination.dirname, mode: 0o700)
        destination.binwrite(contents)
        destination.chmod(0o600)
      end
      verify_bundle(staging, payloads)
      File.rename(staging, output)
    ensure
      FileUtils.remove_entry(staging) if staging.exist?
    end
  end

  def execute(arguments)
    options = parse_options(arguments)
    documents = validate_documents(options)
    validated = documents.fetch(:validated)
    if options.fetch(:validate_only)
      puts "RootFS license/NOTICE bundle inputs are valid " \
        "(#{validated.fetch(:sources).length} open source origins, " \
        "#{validated.fetch(:remote_payloads).length} remote payloads, " \
        "#{validated.fetch(:aports_paths).length} aports files)."
      return
    end

    source_bundle =
      resolve_external_directory(options.fetch(:source_bundle), "--source-bundle")
    license_review =
      resolve_external_directory(options.fetch(:license_review), "--license-review")
    verify_inputs(source_bundle, license_review, documents)

    if options[:output]
      cache =
        if options[:download_cache]
          resolve_external_directory(
            options.fetch(:download_cache),
            "--download-cache"
          )
        end
      inputs = [source_bundle, license_review]
      inputs << cache if cache
      output = validate_new_output(options.fetch(:output), inputs)
      remote_contents = remote_contents_for_output(documents, cache)
      payloads =
        build_payloads(
          source_bundle,
          license_review,
          documents,
          remote_contents
        )
      verify_inputs(source_bundle, license_review, documents)
      materialize(output, payloads)
      puts "Materialized RootFS license/NOTICE candidate bundle at #{output}."
    else
      bundle =
        resolve_external_directory(options.fetch(:verify), "--verify")
      remote_contents = remote_contents_from_bundle(bundle, documents)
      payloads =
        build_payloads(
          source_bundle,
          license_review,
          documents,
          remote_contents
        )
      verify_inputs(source_bundle, license_review, documents)
      verify_bundle(bundle, payloads)
      puts "Verified RootFS license/NOTICE candidate bundle at #{bundle}."
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    RootFSLicenseNoticeBundle.execute(ARGV)
  rescue RootFSLicenseNoticeBundle::BundleError,
    OptionParser::ParseError, JSON::ParserError, SystemCallError => error
    warn error.message
    exit 1
  end
end
