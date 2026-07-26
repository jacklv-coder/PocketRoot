#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "rubygems/package"
require "tmpdir"
require "zlib"
require_relative "../../Scripts/rootfs-source-acquisition"

class RootFSSourceBundleTests < Minitest::Test
  REPOSITORY_ROOT = Pathname(__dir__).join("../..").realpath
  SCRIPT = REPOSITORY_ROOT.join("Scripts/prepare-rootfs-source-bundle.rb")
  ROOTFS_SHA256 =
    "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
  COMMIT = "0123456789abcdef0123456789abcdef01234567"

  def setup
    @temporary_directory = Pathname(Dir.mktmpdir("pocketroot-source-bundle-test-"))
    @snapshot = @temporary_directory.join("demo.tar.gz")
    @distfile = @temporary_directory.join("demo-source.txt")
    @distfile.binwrite("demo source\n")
    write_snapshot(
      @snapshot,
      {"snapshot/main/demo/APKBUILD" => "pkgname=demo\n"}
    )
    @manifest_path = @temporary_directory.join("manifest.json")
    @inventory_path = @temporary_directory.join("inventory.json")
    write_fixture_documents
  end

  def teardown
    FileUtils.remove_entry(@temporary_directory) if @temporary_directory.exist?
  end

  def test_validates_and_materializes_external_bundle
    output = @temporary_directory.join("output")
    stdout, stderr, status = run_script("--output", output.to_s)

    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "Materialized verified RootFS source-review bundle"
    assert_equal "pkgname=demo\n", output.join("aports/demo/APKBUILD").binread
    assert_equal "demo source\n", output.join("distfiles/demo/demo-source.txt").binread
    assert output.join("MATERIALIZATION-RECEIPT.json").file?
    assert output.join("NOTICE.md").file?
    assert output.join("SHA256SUMS").file?
    assert output.join("TREE-MANIFEST.json").file?
    tree_entries = JSON.parse(output.join("TREE-MANIFEST.json").read)
      .fetch("entries")
    tree_paths = tree_entries.map { |entry| entry.fetch("path") }
    assert_equal tree_paths.uniq, tree_paths
    apkbuild_entry = tree_entries.find do |entry|
      entry.fetch("path") == "aports/demo/APKBUILD"
    end
    assert_equal "0644", apkbuild_entry.fetch("mode")

    checksum_lines = output.join("SHA256SUMS").read.lines
    refute checksum_lines.any? { |line| line.end_with?("  SHA256SUMS\n") }
    assert checksum_lines.any? { |line| line.end_with?("  aports/demo/APKBUILD\n") }

    verify_stdout, verify_stderr, verify_status =
      run_script("--verify", output.to_s)
    assert verify_status.success?, "#{verify_stdout}\n#{verify_stderr}"
    assert_includes verify_stdout, "Verified materialized RootFS source-review bundle"
  end

  def test_materializes_from_checksum_verified_download_cache
    cache = @temporary_directory.join("download-cache")
    cache.join("downloads/aports").mkpath
    cache.join("distfiles/demo").mkpath
    FileUtils.copy_file(
      @snapshot,
      cache.join("downloads/aports/demo.tar.gz")
    )
    FileUtils.copy_file(
      @distfile,
      cache.join("distfiles/demo/demo-source.txt")
    )
    @snapshot.delete
    @distfile.delete
    output = @temporary_directory.join("cached-output")

    stdout, stderr, status = run_script(
      "--download-cache",
      cache.to_s,
      "--output",
      output.to_s
    )

    assert status.success?, "#{stdout}\n#{stderr}"
    assert_equal "pkgname=demo\n",
      output.join("aports/demo/APKBUILD").binread
    assert_equal "demo source\n",
      output.join("distfiles/demo/demo-source.txt").binread
    _verify_stdout, verify_stderr, verify_status =
      run_script("--verify", output.to_s)
    assert verify_status.success?, verify_stderr
  end

  def test_rejects_download_cache_digest_mismatch_without_output
    cache = @temporary_directory.join("download-cache-mismatch")
    cache.join("downloads/aports").mkpath
    cache.join("distfiles/demo").mkpath
    cache.join("downloads/aports/demo.tar.gz").binwrite("wrong\n")
    FileUtils.copy_file(
      @distfile,
      cache.join("distfiles/demo/demo-source.txt")
    )
    output = @temporary_directory.join("cache-mismatch-output")

    _stdout, stderr, status = run_script(
      "--download-cache",
      cache.to_s,
      "--output",
      output.to_s
    )

    refute status.success?
    assert_includes stderr, "SHA-512 mismatch"
    refute output.exist?
  end

  def test_rejects_symlink_in_download_cache
    cache = @temporary_directory.join("download-cache-symlink")
    cache.join("downloads/aports").mkpath
    cache.join("distfiles/demo").mkpath
    cache.join("downloads/aports/demo.tar.gz").make_symlink(@snapshot)
    FileUtils.copy_file(
      @distfile,
      cache.join("distfiles/demo/demo-source.txt")
    )
    output = @temporary_directory.join("cache-symlink-output")

    _stdout, stderr, status = run_script(
      "--download-cache",
      cache.to_s,
      "--output",
      output.to_s
    )

    refute status.success?
    assert_includes stderr, "must not contain a symlink"
    refute output.exist?
  end

  def test_rejects_repository_local_download_cache
    output = @temporary_directory.join("repository-cache-output")

    _stdout, stderr, status = run_script(
      "--download-cache",
      REPOSITORY_ROOT.to_s,
      "--output",
      output.to_s
    )

    refute status.success?
    assert_includes stderr,
      "--download-cache must be outside the repository"
    refute output.exist?
  end

  def test_rejects_output_nested_in_download_cache
    cache = @temporary_directory.join("overlapping-cache")
    cache.mkpath
    output = cache.join("nested-output")

    _stdout, stderr, status = run_script(
      "--download-cache",
      cache.to_s,
      "--output",
      output.to_s
    )

    refute status.success?
    assert_includes stderr,
      "--output must not overlap an input directory"
    refute output.exist?
  end

  def test_materialization_preserves_and_verifies_executable_mode
    write_snapshot(
      @snapshot,
      {"snapshot/main/demo/APKBUILD" => "pkgname=demo\n"},
      {},
      modes: {"snapshot/main/demo/APKBUILD" => 0o755}
    )
    manifest = JSON.parse(@manifest_path.read)
    snapshot = manifest.fetch("sources").first.fetch("aportsSnapshot")
    snapshot["sha512"] = Digest::SHA512.file(@snapshot).hexdigest
    snapshot["canonicalTreeSha256"] =
      canonical_tree_digest(
        "main/demo/APKBUILD",
        "pkgname=demo\n",
        mode: 0o755
      )
    @manifest_path.write("#{JSON.pretty_generate(manifest)}\n")
    output = @temporary_directory.join("executable-mode-output")

    _stdout, stderr, status = run_script("--output", output.to_s)

    assert status.success?, stderr
    materialized = output.join("aports/demo/APKBUILD")
    assert_equal 0o755, materialized.lstat.mode & 0o777

    materialized.chmod(0o644)
    refresh_self_authored_integrity(output)
    _verify_stdout, verify_stderr, verify_status =
      run_script("--verify", output.to_s)
    refute verify_status.success?
    assert_includes verify_stderr,
      "bundle aports tree does not match the pinned manifest"
  end

  def test_validate_only_rejects_inventory_drift
    inventory = JSON.parse(@inventory_path.read)
    inventory.fetch("sourceOrigins").first["binaryPackages"] = ["other"]
    @inventory_path.write("#{JSON.pretty_generate(inventory)}\n")

    _stdout, stderr, status = run_script("--validate-only")

    refute status.success?
    assert_includes stderr, "does not match generated inventory"
  end

  def test_shared_validator_rejects_malformed_snapshot_digest
    manifest = JSON.parse(
      REPOSITORY_ROOT.join(
        "Compliance/RootFS/v0.3.3/SOURCE-ACQUISITION.json"
      ).read
    )
    inventory = JSON.parse(
      REPOSITORY_ROOT.join(
        "Compliance/RootFS/v0.3.3/SOURCE-INVENTORY.json"
      ).read
    )
    manifest.fetch("sources").first
      .fetch("aportsSnapshot")["canonicalTreeSha256"] = "invalid"

    error = assert_raises(RootFSSourceAcquisition::ValidationError) do
      RootFSSourceAcquisition.validate_manifest(manifest, inventory)
    end
    assert_includes error.message, "canonicalTreeSha256 has an invalid format"
  end

  def test_shared_validator_rejects_missing_pinned_distfile
    manifest = JSON.parse(
      REPOSITORY_ROOT.join(
        "Compliance/RootFS/v0.3.3/SOURCE-ACQUISITION.json"
      ).read
    )
    inventory = JSON.parse(
      REPOSITORY_ROOT.join(
        "Compliance/RootFS/v0.3.3/SOURCE-INVENTORY.json"
      ).read
    )
    manifest.fetch("sources").first.fetch("distfiles").pop

    error = assert_raises(RootFSSourceAcquisition::ValidationError) do
      RootFSSourceAcquisition.validate_manifest(manifest, inventory)
    end
    assert_includes error.message, "does not match the pinned v0.3.3 inventory"
  end

  def test_fixture_marker_cannot_bypass_production_coverage
    manifest = JSON.parse(@manifest_path.read)
    inventory = JSON.parse(@inventory_path.read)
    source = manifest.fetch("sources").first
    source.fetch("aportsSnapshot")["url"] =
      "https://gitlab.alpinelinux.org/api/v4/projects/alpine%2Faports/" \
      "repository/archive.tar.gz?sha=#{COMMIT}&path=main%2Fdemo"
    source.fetch("distfiles").first["retrievalURLs"] =
      ["https://example.com/demo-source.txt"]

    error = assert_raises(RootFSSourceAcquisition::ValidationError) do
      RootFSSourceAcquisition.validate_manifest(manifest, inventory)
    end
    assert_includes error.message, "no pinned distfile inventory is defined"
  end

  def test_verify_rejects_self_authored_manifest_change
    output = @temporary_directory.join("self-authored-output")
    _stdout, stderr, status = run_script("--output", output.to_s)
    assert status.success?, stderr

    bundled_manifest_path = output.join("SOURCE-ACQUISITION.json")
    bundled_manifest = JSON.parse(bundled_manifest_path.read)
    bundled_manifest.fetch("sources").first.fetch("distfiles").clear
    bundled_manifest_path.write("#{JSON.pretty_generate(bundled_manifest)}\n")
    refresh_self_authored_integrity(output)

    _verify_stdout, verify_stderr, verify_status =
      run_script("--verify", output.to_s)
    refute verify_status.success?
    assert_includes verify_stderr,
      "bundle source acquisition manifest does not match the pinned manifest"
  end

  def test_verify_rejects_external_distfile_symlink
    output = @temporary_directory.join("external-symlink-output")
    _stdout, stderr, status = run_script("--output", output.to_s)
    assert status.success?, stderr

    bundled_distfile = output.join("distfiles/demo/demo-source.txt")
    external_distfile = @temporary_directory.join("external-demo-source.txt")
    FileUtils.copy_file(bundled_distfile, external_distfile)
    bundled_distfile.delete
    File.symlink(external_distfile, bundled_distfile)
    refresh_self_authored_integrity(output)

    _verify_stdout, verify_stderr, verify_status =
      run_script("--verify", output.to_s)
    refute verify_status.success?
    assert_includes verify_stderr, "must not contain a symlink"
  end

  def test_verify_rejects_unsupported_filesystem_node
    output = @temporary_directory.join("unsupported-node-output")
    _stdout, stderr, status = run_script("--output", output.to_s)
    assert status.success?, stderr
    assert system("mkfifo", output.join("unsupported-node").to_s)

    _verify_stdout, verify_stderr, verify_status =
      run_script("--verify", output.to_s)
    refute verify_status.success?
    assert_includes verify_stderr,
      "bundle contains an unsupported filesystem node"
  end

  def test_verify_distinguishes_regular_file_from_equivalent_symlink
    contents = "identical\n"
    write_snapshot(
      @snapshot,
      {
        "snapshot/main/demo/A" => contents,
        "snapshot/main/demo/B" => contents
      }
    )
    manifest = JSON.parse(@manifest_path.read)
    snapshot = manifest.fetch("sources").first.fetch("aportsSnapshot")
    snapshot["sha512"] = Digest::SHA512.file(@snapshot).hexdigest
    snapshot["regularFileCount"] = 2
    digest = Digest::SHA256.hexdigest(contents)
    snapshot["canonicalTreeSha256"] = Digest::SHA256.hexdigest(
      "file\0main/demo/A\0" \
      "0644\0#{digest}\0" \
      "file\0main/demo/B\0" \
      "0644\0#{digest}\0"
    )
    @manifest_path.write("#{JSON.pretty_generate(manifest)}\n")
    output = @temporary_directory.join("node-type-output")
    _stdout, stderr, status = run_script("--output", output.to_s)
    assert status.success?, stderr

    replaced = output.join("aports/demo/A")
    replaced.delete
    File.symlink("B", replaced)
    receipt_path = output.join("MATERIALIZATION-RECEIPT.json")
    receipt = JSON.parse(receipt_path.read)
    receipt.fetch("sources").first["aportsSymlinks"] = [
      {
        "path" => "main/demo/A",
        "target" => "B"
      }
    ]
    receipt_path.write("#{JSON.pretty_generate(receipt)}\n")
    tree_manifest_path = output.join("TREE-MANIFEST.json")
    tree_manifest = JSON.parse(tree_manifest_path.read)
    tree_entry = tree_manifest.fetch("entries")
      .find { |entry| entry["path"] == "aports/demo/A" }
    tree_entry.replace(
      "path" => "aports/demo/A",
      "type" => "symlink",
      "target" => "B"
    )
    tree_manifest_path.write("#{JSON.pretty_generate(tree_manifest)}\n")
    refresh_self_authored_integrity(output)

    _verify_stdout, verify_stderr, verify_status =
      run_script("--verify", output.to_s)
    refute verify_status.success?
    assert_includes verify_stderr,
      "bundle aports tree does not match the pinned manifest"
  end

  def test_materialization_revalidates_the_extracted_tree
    probe_upper = @temporary_directory.join("case-probe")
    probe_lower = @temporary_directory.join("CASE-PROBE")
    probe_upper.binwrite("probe")
    skip "filesystem is case-sensitive" unless probe_lower.exist?
    probe_upper.delete

    contents = "same\n"
    write_snapshot(
      @snapshot,
      {
        "snapshot/main/demo/A" => contents,
        "snapshot/main/demo/a" => contents
      }
    )
    manifest = JSON.parse(@manifest_path.read)
    snapshot = manifest.fetch("sources").first.fetch("aportsSnapshot")
    snapshot["sha512"] = Digest::SHA512.file(@snapshot).hexdigest
    snapshot["regularFileCount"] = 2
    digest = Digest::SHA256.hexdigest(contents)
    snapshot["canonicalTreeSha256"] = Digest::SHA256.hexdigest(
      "file\0main/demo/A\0" \
      "0644\0#{digest}\0" \
      "file\0main/demo/a\0" \
      "0644\0#{digest}\0"
    )
    @manifest_path.write("#{JSON.pretty_generate(manifest)}\n")

    output = @temporary_directory.join("case-collision-output")
    _stdout, stderr, status = run_script("--output", output.to_s)

    refute status.success?
    assert_includes stderr,
      "extracted aports tree does not match the pinned manifest"
    refute output.exist?
  end

  def test_streaming_download_limit_stops_oversized_unknown_length_response
    manifest = JSON.parse(@manifest_path.read)
    manifest.fetch("sources").first
      .fetch("aportsSnapshot")["url"] = "https://example.invalid/snapshot"
    @manifest_path.write("#{JSON.pretty_generate(manifest)}\n")
    fake_bin = @temporary_directory.join("fake-bin")
    fake_bin.mkpath
    fake_curl = fake_bin.join("curl")
    fake_curl.write(<<~SH)
      #!/bin/sh
      /usr/bin/head -c 9000000 /dev/zero
    SH
    fake_curl.chmod(0o755)
    output = @temporary_directory.join("oversized-output")

    _stdout, stderr, status = run_script(
      "--output",
      output.to_s,
      environment: {
        "PATH" => "#{fake_bin}:#{ENV.fetch("PATH")}"
      }
    )

    refute status.success?
    assert_includes stderr, "exceeds 8388608 bytes"
    refute output.exist?
  end

  def test_verify_rejects_extra_external_symlink
    output = @temporary_directory.join("extra-symlink-output")
    _stdout, stderr, status = run_script("--output", output.to_s)
    assert status.success?, stderr
    File.symlink("/etc/passwd", output.join("external-link"))
    refresh_self_authored_integrity(output)

    _verify_stdout, verify_stderr, verify_status =
      run_script("--verify", output.to_s)
    refute verify_status.success?
    assert_includes verify_stderr,
      "bundle symlink set does not match the pinned aports trees"
  end

  def test_verify_rejects_extra_regular_file_with_refreshed_metadata
    output = @temporary_directory.join("extra-file-output")
    _stdout, stderr, status = run_script("--output", output.to_s)
    assert status.success?, stderr

    extra = output.join("distfiles/demo/extra.txt")
    extra.binwrite("extra\n")
    tree_manifest_path = output.join("TREE-MANIFEST.json")
    tree_manifest = JSON.parse(tree_manifest_path.read)
    tree_manifest.fetch("entries") << {
      "path" => "distfiles/demo/extra.txt",
      "type" => "file",
      "sha256" => Digest::SHA256.file(extra).hexdigest
    }
    tree_manifest["entries"].sort_by! { |entry| entry.fetch("path") }
    tree_manifest_path.write("#{JSON.pretty_generate(tree_manifest)}\n")
    refresh_self_authored_integrity(output)

    _verify_stdout, verify_stderr, verify_status =
      run_script("--verify", output.to_s)
    refute verify_status.success?
    assert_includes verify_stderr,
      "bundle path/type set does not match the pinned source manifest"
  end

  def test_rejects_checksum_mismatch_without_promoting_output
    manifest = JSON.parse(@manifest_path.read)
    manifest.fetch("sources").first.fetch("distfiles").first["sha512"] = "0" * 128
    @manifest_path.write("#{JSON.pretty_generate(manifest)}\n")
    output = @temporary_directory.join("failed-output")

    _stdout, stderr, status = run_script("--output", output.to_s)

    refute status.success?
    assert_includes stderr, "SHA-512 mismatch"
    refute output.exist?
  end

  def test_rejects_repository_output
    output = REPOSITORY_ROOT.join("source-bundle-test-output")

    _stdout, stderr, status = run_script("--output", output.to_s)

    refute status.success?
    assert_includes stderr, "--output must be outside the repository"
    refute output.exist?
  end

  def test_rejects_file_urls_without_explicit_fixture_gate
    _stdout, stderr, status = run_script("--validate-only", allow_file_urls: false)

    refute status.success?
    assert_includes stderr, "must use https"
  end

  def test_rejects_unsafe_snapshot_member
    write_snapshot(@snapshot, {"snapshot/../escape" => "bad\n"})
    manifest = JSON.parse(@manifest_path.read)
    snapshot = manifest.fetch("sources").first.fetch("aportsSnapshot")
    snapshot["sha512"] = Digest::SHA512.file(@snapshot).hexdigest
    snapshot["regularFileCount"] = 1
    snapshot["canonicalTreeSha256"] = "0" * 64
    @manifest_path.write("#{JSON.pretty_generate(manifest)}\n")
    output = @temporary_directory.join("unsafe-output")

    _stdout, stderr, status = run_script("--output", output.to_s)

    refute status.success?
    assert_includes stderr, "unsafe tar member"
    refute output.exist?
  end

  def test_materializes_safe_snapshot_symlink
    write_snapshot(
      @snapshot,
      {"snapshot/main/demo/APKBUILD" => "pkgname=demo\n"},
      {"snapshot/main/demo/duplicate" => "APKBUILD"}
    )
    manifest = JSON.parse(@manifest_path.read)
    snapshot = manifest.fetch("sources").first.fetch("aportsSnapshot")
    snapshot["sha512"] = Digest::SHA512.file(@snapshot).hexdigest
    snapshot["regularFileCount"] = 2
    file_digest = Digest::SHA256.hexdigest("pkgname=demo\n")
    snapshot["canonicalTreeSha256"] = Digest::SHA256.hexdigest(
      "file\0main/demo/APKBUILD\0" \
      "0644\0#{file_digest}\0" \
      "symlink\0main/demo/duplicate\0APKBUILD\0#{file_digest}\0"
    )
    @manifest_path.write("#{JSON.pretty_generate(manifest)}\n")
    output = @temporary_directory.join("symlink-output")

    stdout, stderr, status = run_script("--output", output.to_s)

    assert status.success?, "#{stdout}\n#{stderr}"
    assert output.join("aports/demo/duplicate").symlink?
    assert_equal "APKBUILD", output.join("aports/demo/duplicate").readlink.to_s

    _verify_stdout, verify_stderr, verify_status =
      run_script("--verify", output.to_s)
    assert verify_status.success?, verify_stderr

    output.join("aports/demo/duplicate").delete
    File.symlink("other-target", output.join("aports/demo/duplicate"))
    _changed_stdout, changed_stderr, changed_status =
      run_script("--verify", output.to_s)
    refute changed_status.success?
    assert_includes changed_stderr,
      "materialized symlink does not target a regular file"
  end

  private

  def write_snapshot(path, files, symlinks = {}, modes: {})
    Zlib::GzipWriter.open(path.to_s) do |gzip|
      Gem::Package::TarWriter.new(gzip) do |tar|
        files.each do |name, contents|
          tar.add_file_simple(
            name,
            modes.fetch(name, 0o644),
            contents.bytesize
          ) do |entry|
            entry.write(contents)
          end
        end
        symlinks.each do |name, target|
          tar.add_symlink(name, target, 0o777)
        end
      end
    end
  end

  def file_url(path)
    "file://#{path}"
  end

  def canonical_tree_digest(relative_path, contents, mode: 0o644)
    file_digest = Digest::SHA256.hexdigest(contents)
    Digest::SHA256.hexdigest(
      "file\0#{relative_path}\0#{format("%04o", mode)}\0#{file_digest}\0"
    )
  end

  def refresh_self_authored_integrity(root)
    tree_manifest_path = root.join("TREE-MANIFEST.json")
    tree_manifest = JSON.parse(tree_manifest_path.read)
    tree_manifest.fetch("entries").each do |entry|
      next unless entry.fetch("type") == "file"

      entry["sha256"] = Digest::SHA256.file(root.join(entry.fetch("path"))).hexdigest
    end
    tree_manifest_path.write("#{JSON.pretty_generate(tree_manifest)}\n")

    checksum_lines = root.glob("**/*", File::FNM_DOTMATCH)
      .select { |path| path.lstat.file? }
      .reject { |path| path == root.join("SHA256SUMS") }
      .map do |path|
        relative = path.relative_path_from(root).to_s
        "#{Digest::SHA256.file(path).hexdigest}  #{relative}"
      end
      .sort
    root.join("SHA256SUMS").write("#{checksum_lines.join("\n")}\n")
  end

  def write_fixture_documents
    archive = {
      "version" => "v0.3.3",
      "sha256" => ROOTFS_SHA256
    }
    inventory = {
      "schemaVersion" => 1,
      "archive" => archive,
      "sourceOrigins" => [
        {
          "sourceOrigin" => "demo",
          "aportsCommit" => COMMIT,
          "binaryPackages" => ["demo"],
          "declaredLicenseExpressions" => ["MIT"]
        }
      ]
    }
    manifest = {
      "schemaVersion" => 1,
      "testFixture" => true,
      "archive" => archive,
      "aportsCanonicalTreeFormat" => "typed-path-mode-sha256-v1",
      "bundleStatus" => "external-materialization-required",
      "redistributionApproved" => false,
      "sources" => [
        {
          "sourceOrigin" => "demo",
          "aportsCommit" => COMMIT,
          "binaryPackages" => ["demo"],
          "declaredLicenseExpressions" => ["MIT"],
          "aportsSnapshot" => {
            "path" => "main/demo",
            "url" => file_url(@snapshot),
            "sha512" => Digest::SHA512.file(@snapshot).hexdigest,
            "regularFileCount" => 1,
            "canonicalTreeSha256" =>
              canonical_tree_digest("main/demo/APKBUILD", "pkgname=demo\n")
          },
          "distfiles" => [
            {
              "filename" => "demo-source.txt",
              "retrievalURLs" => [file_url(@distfile)],
              "sha512" => Digest::SHA512.file(@distfile).hexdigest
            }
          ]
        }
      ]
    }
    @inventory_path.write("#{JSON.pretty_generate(inventory)}\n")
    @manifest_path.write("#{JSON.pretty_generate(manifest)}\n")
  end

  def run_script(*arguments, allow_file_urls: true, environment: {})
    environment = environment.dup
    environment["POCKETROOT_TEST_ALLOW_FILE_URLS"] = "1" if allow_file_urls
    Open3.capture3(
      environment,
      RbConfig.ruby,
      SCRIPT.to_s,
      "--manifest", @manifest_path.to_s,
      "--source-inventory", @inventory_path.to_s,
      *arguments,
      chdir: REPOSITORY_ROOT.to_s
    )
  end
end
