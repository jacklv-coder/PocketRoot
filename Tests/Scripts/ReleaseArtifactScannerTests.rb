#!/usr/bin/env ruby

require "fileutils"
require "json"
require "minitest/autorun"
require "pathname"
require "rbconfig"
require "stringio"
require "tmpdir"
require_relative "../../Scripts/scan-release-artifact"

class ReleaseArtifactScannerTests < Minitest::Test
  Scanner = PocketRootReleaseArtifactScanner

  class FakeRunner
    attr_accessor :archive_application_properties
    attr_accessor :archive_application_path
    attr_accessor :dependencies
    attr_accessor :entitlements
    attr_accessor :entitlements_readable
    attr_accessor :map_jit
    attr_accessor :nm_success
    attr_accessor :on_lipo
    attr_accessor :signed
    attr_accessor :signed_paths
    attr_accessor :signature_probe_stderr
    attr_accessor :signature_valid

    def initialize
      @archive_application_path =
        "Applications/PocketRootRuntime.app"
      @archive_application_properties = nil
      @dependencies = [
        "/System/Library/Frameworks/Foundation.framework/Foundation"
      ]
      @entitlements = {}
      @entitlements_readable = true
      @map_jit = false
      @nm_success = true
      @on_lipo = nil
      @signed = false
      @signed_paths = {}
      @signature_probe_stderr = "code object is not signed at all"
      @signature_valid = true
    end

    def run(command, stdin_data: "")
      tool = command.first
      case tool
      when "/usr/bin/plutil"
        if command.last == "-"
          if stdin_data == "<plist/>"
            result(JSON.generate(@pending_entitlements || @entitlements))
          elsif stdin_data == "archive plist"
            result(
              JSON.generate(
                {
                  "ApplicationProperties" =>
                    @archive_application_properties ||
                    {"ApplicationPath" => @archive_application_path}
                }
              )
            )
          else
            result(application_info_json)
          end
        else
          result(application_info_json)
        end
      when "/usr/bin/lipo"
        @on_lipo.call if @on_lipo
        result("Non-fat file: app is architecture: arm64\n")
      when "/usr/bin/otool"
        lines = ["app:"]
        lines.concat(
          @dependencies.map do |dependency|
            "\t#{dependency} (compatibility version 1.0.0, current version 1.0.0)"
          end
        )
        result("#{lines.join("\n")}\n")
      when "/usr/bin/nm"
        result("                 U _malloc\n", "", @nm_success)
      when "/usr/bin/strings"
        result(@map_jit ? "prefix MAP_JIT suffix\n" : "ordinary string\n")
      when "/usr/bin/codesign"
        code_object = command.last
        if command.include?("--entitlements")
          @pending_entitlements =
            @entitlements_by_path &&
            @entitlements_by_path[File.basename(code_object)]
          @pending_entitlements ||= @entitlements
          result("<plist/>", "", @entitlements_readable)
        elsif command.include?("--verify")
          result("", "", @signature_valid)
        else
          signed =
            if @signed_paths.key?(File.basename(code_object))
              @signed_paths.fetch(File.basename(code_object))
            else
              @signed
            end
          result("", @signature_probe_stderr, signed)
        end
      else
        raise "unexpected fake command: #{command.inspect}"
      end
    end

    private

    def application_info_json
      JSON.generate(
        {
          "CFBundleIdentifier" =>
            "com.jacklv.PocketRootIshRuntimeCompileSpike",
          "CFBundleExecutable" => "PocketRootRuntime",
          "CFBundleDisplayName" => "PocketRoot Runtime",
          "CFBundleShortVersionString" => "0.1.0",
          "CFBundleVersion" => "1",
          "MinimumOSVersion" => "18.0",
          "DTPlatformName" => "iphoneos",
          "DTSDKName" => "iphoneos18.0",
          "UIDeviceFamily" => [1, 2]
        }
      )
    end

    def result(stdout, stderr = "", success = true)
      Scanner::CommandResult.new(stdout, stderr, success)
    end
  end

  def setup
    @temporary_directory =
      Pathname(Dir.mktmpdir("pocketroot-artifact-scanner-test-"))
    @runner = FakeRunner.new
  end

  def teardown
    FileUtils.remove_entry(@temporary_directory) if @temporary_directory.exist?
  end

  def test_scans_unsigned_application_and_keeps_release_gates_closed
    app = application_fixture
    outputs =
      Scanner.build_outputs(
        "app",
        app,
        runner: @runner,
        expected_bundle_identifier:
          "com.jacklv.PocketRootIshRuntimeCompileSpike"
      )
    inventory = JSON.parse(outputs.fetch("ARTIFACT-INVENTORY.json"))
    sbom = JSON.parse(outputs.fetch("SBOM.spdx.json"))

    assert_equal "unsigned", inventory.dig("signature", "status")
    assert_equal 1, inventory.dig("artifact", "directoryCount")
    assert_equal 3, inventory.dig("artifact", "fileCount")
    assert_equal 1, inventory.dig("artifact", "machOFileCount")
    assert_equal ["arm64"],
      inventory.fetch("machOBinaries").fetch(0).fetch("architectures")
    assert Scanner.clean_engineering_signals?(inventory)
    assert inventory.dig("coverage", "engineeringArtifactBuilt")
    assert inventory.dig("coverage", "engineeringArtifactScanned")
    refute inventory.dig("coverage", "signedReleaseArtifact")
    refute inventory.dig("coverage", "exportedReleaseArtifact")
    refute inventory.dig("coverage", "completeReleaseArtifactSBOM")
    refute inventory.dig("coverage", "distributionAuthorized")
    assert_equal 3, sbom.fetch("files").length
    assert_equal 3, sbom.fetch("relationships").length
    assert_equal true, sbom.fetch("packages").fetch(0).fetch("filesAnalyzed")
  end

  def test_outputs_are_deterministic_across_locations_and_creation_order
    first = application_fixture("first", reverse: false)
    second = application_fixture("second", reverse: true)

    first_outputs = Scanner.build_outputs("app", first, runner: @runner)
    second_outputs = Scanner.build_outputs("app", second, runner: @runner)

    assert_equal first_outputs, second_outputs
  end

  def test_spdx_package_verification_code_uses_filename_order
    inventory = {
      "application" => {
        "bundleIdentifier" => "com.example.VerificationOrder",
        "shortVersion" => "1.0"
      },
      "files" => [
        {"path" => "b", "sha1" => "0000000000000000000000000000000000000000",
          "sha256" => "0" * 64},
        {"path" => "a", "sha1" => "ffffffffffffffffffffffffffffffffffffffff",
          "sha256" => "f" * 64}
      ]
    }

    sbom = Scanner.build_sbom(inventory)
    verification_code =
      sbom.fetch("packages").fetch(0).
        fetch("packageVerificationCode").
        fetch("packageVerificationCodeValue")

    assert_equal(
      Digest::SHA1.hexdigest(
        "ffffffffffffffffffffffffffffffffffffffff" \
        "0000000000000000000000000000000000000000"
      ),
      verification_code
    )
  end

  def test_materializes_and_reverifies_exact_external_evidence
    app = application_fixture
    output = @temporary_directory.join("evidence")
    resolved_output = output.parent.realpath.join(output.basename)

    assert_equal(
      resolved_output,
      Scanner.materialize(output, "app", app, runner: @runner)
    )
    assert_equal(
      Scanner::OUTPUT_FILENAMES.sort,
      output.children.map { |path| path.basename.to_s }.sort
    )
    assert Scanner.verify(
      output,
      "app",
      app,
      runner: @runner,
      require_clean: true
    )

    output.join("README.md").binwrite("tampered")
    error = assert_raises(Scanner::ScanError) do
      Scanner.verify(output, "app", app, runner: @runner)
    end
    assert_includes error.message, "stale"
  end

  def test_verify_rejects_empty_directory_added_after_materialization
    app = application_fixture
    output = @temporary_directory.join("directory-bound-evidence")
    Scanner.materialize(output, "app", app, runner: @runner)
    app.join("AddedEmptyDirectory").mkdir

    error = assert_raises(Scanner::ScanError) do
      Scanner.verify(output, "app", app, runner: @runner)
    end

    assert_includes error.message, "stale"
  end

  def test_rejects_nul_in_metadata_path
    error = assert_raises(Scanner::ScanError) do
      Scanner.safe_relative_path("PocketRoot\0Injected", "metadata path")
    end

    assert_includes error.message, "UTF-8 string"
  end

  def test_detects_jit_private_framework_and_private_entitlement_signals
    app = application_fixture
    @runner.signed = true
    @runner.entitlements = {
      "com.apple.private.example" => true,
      "com.apple.security.cs.allow-jit" => true
    }
    @runner.map_jit = true
    @runner.dependencies = [
      "/System/Library/PrivateFrameworks/Secret.framework/Secret"
    ]
    outputs = Scanner.build_outputs("app", app, runner: @runner)
    inventory = JSON.parse(outputs.fetch("ARTIFACT-INVENTORY.json"))

    refute Scanner.clean_engineering_signals?(inventory)
    assert_equal(
      ["com.apple.security.cs.allow-jit"],
      inventory.dig("riskSignals", "jitEntitlements")
    )
    assert_equal(
      ["com.apple.private.example"],
      inventory.dig("riskSignals", "privateEntitlements")
    )
    assert_equal(
      ["PocketRootRuntime"],
      inventory.dig("riskSignals", "mapJITBinaries")
    )
    assert_equal 1,
      inventory.dig("riskSignals", "privateFrameworkDependencies").length

    output = @temporary_directory.join("blocked-evidence")
    Scanner.materialize(output, "app", app, runner: @runner)
    error = assert_raises(Scanner::ScanError) do
      Scanner.verify(
        output,
        "app",
        app,
        runner: @runner,
        require_clean: true
      )
    end
    assert_includes error.message, "blocked engineering risk signals"
  end

  def test_unsigned_outer_app_does_not_hide_nested_code_entitlements
    app = application_fixture
    nested = app.join("Frameworks/Nested")
    nested.parent.mkpath
    nested.binwrite(mach_o_fixture)
    nested.chmod(0o755)
    @runner.signed_paths["Nested"] = true
    @runner.instance_variable_set(
      :@entitlements_by_path,
      {"Nested" => {"com.apple.security.cs.allow-jit" => true}}
    )

    inventory = Scanner.build_inventory("app", app, runner: @runner)

    assert_equal "unsigned", inventory.dig("signature", "status")
    nested_binary =
      inventory.fetch("machOBinaries").find do |binary|
        binary.fetch("path") == "Frameworks/Nested"
      end
    assert_equal "signed-valid",
      nested_binary.dig("signature", "status")
    assert_equal(
      ["com.apple.security.cs.allow-jit"],
      inventory.dig("riskSignals", "jitEntitlements")
    )
    refute Scanner.clean_engineering_signals?(inventory)
  end

  def test_detects_invalid_existing_signature
    app = application_fixture
    @runner.signed = true
    @runner.signature_valid = false

    inventory =
      Scanner.build_inventory("app", app, runner: @runner)

    assert_equal "signed-invalid", inventory.dig("signature", "status")
    assert inventory.dig("riskSignals", "invalidSignature")
    refute Scanner.clean_engineering_signals?(inventory)
  end

  def test_does_not_treat_cafebabe_resource_as_mach_o
    app = application_fixture
    app.join("Example.class").binwrite(
      [0xcafebabe, 0, 52, 1].pack("N4") + "java class payload"
    )

    inventory =
      Scanner.build_inventory("app", app, runner: @runner)

    resource =
      inventory.fetch("files").find do |file|
        file.fetch("path") == "Example.class"
      end
    refute resource.fetch("machO")
    assert_equal 1, inventory.dig("artifact", "machOFileCount")
  end

  def test_rejects_unbounded_mach_o_command_table_without_reading_it
    path = @temporary_directory.join("OversizedCommands")
    header = [
      0xfeedfacf,
      0x0100000c,
      0,
      2,
      1,
      Scanner::MAXIMUM_MACH_O_COMMAND_BYTES + 1,
      0,
      0
    ].pack("N8")
    path.binwrite(header)
    File.open(path, "ab") do |file|
      file.truncate(
        header.bytesize + Scanner::MAXIMUM_MACH_O_COMMAND_BYTES + 1
      )
    end

    File.open(path, "rb") do |file|
      refute Scanner.valid_macho_file?(file, file.stat.size)
      assert_operator file.pos, :<, 128
    end
  end

  def test_fails_closed_when_binary_or_signature_analysis_is_inconclusive
    app = application_fixture
    @runner.nm_success = false

    error = assert_raises(Scanner::ScanError) do
      Scanner.build_inventory("app", app, runner: @runner)
    end
    assert_includes error.message, "nm"

    @runner.nm_success = true
    @runner.signature_probe_stderr = "unexpected codesign failure"
    error = assert_raises(Scanner::ScanError) do
      Scanner.build_inventory("app", app, runner: @runner)
    end
    assert_includes error.message, "could not determine"

    @runner.signed = true
    @runner.entitlements_readable = false
    error = assert_raises(Scanner::ScanError) do
      Scanner.build_inventory("app", app, runner: @runner)
    end
    assert_includes error.message, "could not read"
  end

  def test_scans_application_selected_by_xcarchive_metadata
    archive = @temporary_directory.join("PocketRoot.xcarchive")
    archive.mkpath
    archive.join("Info.plist").binwrite("archive plist")
    app =
      application_fixture(
        "PocketRoot.xcarchive/Products/Applications/PocketRootRuntime"
      )

    inventory =
      Scanner.build_inventory("xcarchive", archive, runner: @runner)

    assert_equal "xcarchive", inventory.dig("input", "kind")
    assert_equal(
      "Products/Applications/PocketRootRuntime.app",
      inventory.dig("input", "applicationRelativePath")
    )
    assert_equal app.basename.to_s, "PocketRootRuntime.app"
  end

  def test_fat_macho_dependency_parser_ignores_architecture_headers
    output = <<~OTOOL
      App (architecture x86_64):
        /usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)
      App (architecture arm64):
        /usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)
        /System/Library/Frameworks/UIKit.framework/UIKit (compatibility version 1.0.0, current version 1.0.0)
    OTOOL

    assert_equal(
      [
        "/System/Library/Frameworks/UIKit.framework/UIKit",
        "/usr/lib/libSystem.B.dylib"
      ],
      Scanner.parse_dependencies(output)
    )
  end

  def test_dependency_parser_rejects_unrecognized_non_header_lines
    output = <<~OTOOL
      App:
        /usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)
        /System/Library/PrivateFrameworks/Secret.framework/Secret
    OTOOL

    error = assert_raises(Scanner::ScanError) do
      Scanner.parse_dependencies(output)
    end

    assert_includes error.message, "unrecognized dependency line"
  end

  def test_rejects_archive_application_escape_and_symlink
    archive = @temporary_directory.join("Unsafe.xcarchive")
    archive.mkpath
    archive.join("Info.plist").binwrite("archive plist")
    @runner.archive_application_path = "../../Outside.app"

    error = assert_raises(Scanner::ScanError) do
      Scanner.build_inventory("xcarchive", archive, runner: @runner)
    end
    assert_includes error.message, "contained relative path"

    @runner.archive_application_path =
      "Applications/PocketRootRuntime.app"
    archive.join("Products").mkpath
    real_app = application_fixture("real")
    File.symlink(
      real_app,
      archive.join("Products/Applications")
    )
    error = assert_raises(Scanner::ScanError) do
      Scanner.build_inventory("xcarchive", archive, runner: @runner)
    end
    assert_includes error.message, "contains a symlink"
  end

  def test_rejects_non_dictionary_archive_application_properties
    archive = @temporary_directory.join("Malformed.xcarchive")
    archive.mkpath
    archive.join("Info.plist").binwrite("archive plist")
    @runner.archive_application_properties = "not a dictionary"

    error = assert_raises(Scanner::ScanError) do
      Scanner.build_inventory("xcarchive", archive, runner: @runner)
    end

    assert_includes error.message, "ApplicationProperties"
    assert_includes error.message, "dictionary"
  end

  def test_rejects_symlink_and_oversized_file_in_application_tree
    app = application_fixture
    File.symlink(app.join("Resource.txt"), app.join("Linked.txt"))

    error = assert_raises(Scanner::ScanError) do
      Scanner.build_inventory("app", app, runner: @runner)
    end
    assert_includes error.message, "contains a symlink"

    app.join("Linked.txt").unlink
    oversized = app.join("Oversized.bin")
    File.open(oversized, "wb") do |file|
      file.truncate(Scanner::MAXIMUM_FILE_BYTES + 1)
    end
    error = assert_raises(Scanner::ScanError) do
      Scanner.build_inventory("app", app, runner: @runner)
    end
    assert_includes error.message, "exceeds"
  end

  def test_digest_stream_stops_after_the_inventoried_size
    stream = StringIO.new("expected-unbounded-trailing-data")

    error = assert_raises(Scanner::ScanError) do
      Scanner.digest_stream(stream, 8, "Growing.bin")
    end

    assert_includes error.message, "changed during scan"
    assert_equal 9, stream.pos
  end

  def test_rejects_oversized_info_plist_before_snapshotting_it
    app = application_fixture
    File.open(app.join("Info.plist"), "wb") do |file|
      file.truncate(Scanner::MAXIMUM_PROPERTY_LIST_BYTES + 1)
    end

    error = assert_raises(Scanner::ScanError) do
      Scanner.build_inventory("app", app, runner: @runner)
    end

    assert_includes error.message, "Info.plist"
    assert_includes error.message,
      "exceeds #{Scanner::MAXIMUM_PROPERTY_LIST_BYTES} bytes"
  end

  def test_directory_entries_are_included_in_the_traversal_limit
    app = application_fixture
    app.join("Empty").mkdir

    error = assert_raises(Scanner::ScanError) do
      Scanner.inventory_files(app, maximum_entry_count: 3)
    end

    assert_includes error.message, "filesystem entries"
  end

  def test_rejects_unreadable_application_directory
    app = application_fixture
    hidden = app.join("Hidden.framework")
    hidden.mkpath
    hidden.join("Hidden").binwrite(mach_o_fixture)
    hidden.chmod(0o000)
    if hidden.readable? && hidden.executable?
      skip "current privileges bypass directory permission bits"
    end

    error = assert_raises(Scanner::ScanError) do
      Scanner.build_inventory("app", app, runner: @runner)
    end
    assert_includes error.message, "unreadable directory"
  ensure
    hidden.chmod(0o700) if hidden && hidden.exist?
  end

  def test_rejects_parent_directory_replaced_by_symlink
    app = application_fixture
    framework = app.join("Frameworks")
    framework.mkdir
    expected = framework.lstat
    outside = @temporary_directory.join("outside")
    outside.mkdir
    outside.join("External").binwrite("external")
    original = app.join("Frameworks-original")
    framework.rename(original)
    File.symlink(outside, framework)

    error = assert_raises(Scanner::ScanError) do
      Scanner.stable_child_lstat(
        framework,
        expected,
        "External",
        "Frameworks"
      )
    end

    assert_includes error.message, "changed during scan"
  end

  def test_system_runner_caps_output_while_reading
    runner = Scanner::SystemRunner.new(maximum_output_bytes: 1_024)

    error = assert_raises(Scanner::ScanError) do
      runner.run(
        [RbConfig.ruby, "-e", "STDOUT.write('x' * 2048)"]
      )
    end

    assert_includes error.message, "tool output exceeds 1024 bytes"
  end

  def test_rejects_bundle_identifier_drift
    app = application_fixture

    error = assert_raises(Scanner::ScanError) do
      Scanner.build_inventory(
        "app",
        app,
        runner: @runner,
        expected_bundle_identifier: "com.example.Unexpected"
      )
    end

    assert_includes error.message, "bundle identifier drifted"
  end

  def test_rejects_info_plist_drift_after_file_hashing
    app = application_fixture
    @runner.on_lipo = lambda do
      app.join("Info.plist").binwrite("changed fixture plist")
      @runner.on_lipo = nil
    end

    error = assert_raises(Scanner::ScanError) do
      Scanner.build_inventory("app", app, runner: @runner)
    end

    assert_includes error.message, "Info.plist"
    assert_includes error.message, "changed during scan"
  end

  def test_rejects_file_added_after_initial_tree_traversal
    app = application_fixture
    @runner.on_lipo = lambda do
      app.join("LatePayload.txt").binwrite("late payload")
      @runner.on_lipo = nil
    end

    error = assert_raises(Scanner::ScanError) do
      Scanner.build_inventory("app", app, runner: @runner)
    end

    assert_includes error.message, "artifact tree changed during scan"
  end

  def test_rejects_relative_in_repository_and_existing_output
    app = application_fixture
    relative_error = assert_raises(Scanner::ScanError) do
      Scanner.materialize(
        Pathname("relative-evidence"),
        "app",
        app,
        runner: @runner
      )
    end
    assert_includes relative_error.message, "must be absolute"

    repository_output =
      Scanner.repository_root.join("Compliance/release-artifact-test")
    repository_error = assert_raises(Scanner::ScanError) do
      Scanner.materialize(
        repository_output,
        "app",
        app,
        runner: @runner
      )
    end
    assert_includes repository_error.message, "outside the repository"
    refute repository_output.exist?

    existing = @temporary_directory.join("existing")
    existing.mkdir
    existing_error = assert_raises(Scanner::ScanError) do
      Scanner.materialize(existing, "app", app, runner: @runner)
    end
    assert_includes existing_error.message, "already exists"
  end

  def test_rejects_evidence_inside_the_scanned_input
    app = application_fixture
    nested_output = app.join("evidence")

    error = assert_raises(Scanner::ScanError) do
      Scanner.materialize(nested_output, "app", app, runner: @runner)
    end

    assert_includes error.message, "must not overlap"
    refute nested_output.exist?
  end

  def test_case_variants_cannot_bypass_filesystem_containment
    root = Scanner.repository_root
    case_variant_root =
      root.parent.join(root.basename.to_s.swapcase)
    unless case_variant_root.exist? &&
      same_filesystem_entry?(case_variant_root, root)
      skip "filesystem is case-sensitive"
    end

    repository_output =
      case_variant_root.join("Compliance/release-artifact-case-test")
    repository_error = assert_raises(Scanner::ScanError) do
      Scanner.resolved_new_output(repository_output)
    end
    assert_includes repository_error.message, "outside the repository"
    refute repository_output.exist?

    app = application_fixture("case-overlap")
    case_variant_app = Pathname(app.to_s.swapcase)
    assert case_variant_app.exist?
    assert same_filesystem_entry?(case_variant_app, app)
    nested_output = case_variant_app.join("evidence")
    overlap_error = assert_raises(Scanner::ScanError) do
      Scanner.materialize(nested_output, "app", app, runner: @runner)
    end
    assert_includes overlap_error.message, "must not overlap"
    refute nested_output.exist?
  end

  def test_rejects_unexpected_evidence_file
    app = application_fixture
    output = @temporary_directory.join("evidence")
    Scanner.materialize(output, "app", app, runner: @runner)
    output.join("unexpected.txt").binwrite("unexpected")

    error = assert_raises(Scanner::ScanError) do
      Scanner.verify(output, "app", app, runner: @runner)
    end
    assert_includes error.message, "file set drifted"
  end

  def test_rejects_oversized_expected_evidence_without_loading_it
    app = application_fixture
    output = @temporary_directory.join("evidence")
    Scanner.materialize(output, "app", app, runner: @runner)
    File.open(output.join("README.md"), "wb") do |file|
      file.truncate(Scanner::MAXIMUM_TOOL_OUTPUT_BYTES + 1)
    end

    error = assert_raises(Scanner::ScanError) do
      Scanner.verify(output, "app", app, runner: @runner)
    end
    assert_includes error.message, "stale"
  end

  def test_rejects_fifo_evidence_without_opening_it
    app = application_fixture
    output = @temporary_directory.join("evidence")
    Scanner.materialize(output, "app", app, runner: @runner)
    output.join("README.md").unlink
    File.mkfifo(output.join("README.md"))

    error = assert_raises(Scanner::ScanError) do
      Scanner.verify(output, "app", app, runner: @runner)
    end

    assert_includes error.message, "stale"
  end

  def test_cli_requires_exactly_one_input_and_mode
    assert_equal 1, Scanner.execute([])
    assert_equal 1,
      Scanner.execute(
        [
          "--app",
          "/tmp/example.app",
          "--xcarchive",
          "/tmp/example.xcarchive",
          "--output",
          "/tmp/evidence"
        ]
      )
    assert_equal 1,
      Scanner.execute(
        [
          "--app",
          "/tmp/example.app",
          "--output",
          "/tmp/evidence",
          "--require-clean"
        ]
      )
  end

  private

  def same_filesystem_entry?(left, right)
    left_stat = left.lstat
    right_stat = right.lstat
    left_stat.dev == right_stat.dev && left_stat.ino == right_stat.ino
  end

  def mach_o_fixture
    [
      0xfeedfacf,
      0x0100000c,
      0,
      2,
      0,
      0,
      0,
      0
    ].pack("N8")
  end

  def application_fixture(name = "fixture", reverse: false)
    app = @temporary_directory.join("#{name}.app")
    app.mkpath
    entries = [
      ["Info.plist", "fixture plist"],
      ["PocketRootRuntime", mach_o_fixture],
      ["Resource.txt", "resource payload\n"]
    ]
    entries.reverse! if reverse
    entries.each do |relative, contents|
      destination = app.join(relative)
      destination.parent.mkpath
      destination.binwrite(contents)
      destination.chmod(relative == "PocketRootRuntime" ? 0o755 : 0o644)
    end
    app
  end
end
