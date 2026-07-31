#!/usr/bin/env ruby

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "stringio"
require "tmpdir"
require_relative "../../Scripts/verify-source-release"

class SourceReleaseVerificationTests < Minitest::Test
  REPOSITORY_ROOT = Pathname(__dir__).join("../..").realpath

  def setup
    @temporary_directory = Pathname(Dir.mktmpdir("pocketroot-source-release-test-"))
  end

  def teardown
    FileUtils.remove_entry(@temporary_directory) if @temporary_directory.exist?
  end

  def test_current_release_commit_passes_source_archive_audit
    result = PocketRootSourceRelease.verify(
      root: REPOSITORY_ROOT,
      ref: "HEAD",
      version: "0.1.0"
    )

    assert_equal "ready", result.fetch("sourceTrack")
    refute result.fetch("rootFSIncluded")
    refute result.fetch("runtimeArtifactIncluded")
    assert_match(/\A[0-9a-f]{64}\z/, result.fetch("archiveSha256"))
    assert_operator result.fetch("regularFileCount"), :>, 100
  end

  def test_rejects_git_archive_export_filtering_in_candidate_ref
    repository = release_repository(
      version: "0.1.0",
      authorized_version: "0.1.0"
    )
    payload_path = repository.join("Payload/runtime.md")
    payload_path.dirname.mkpath
    payload_path.binwrite("%PDF-1.4\n")
    repository.join(".gitattributes").binwrite(
      ".gitattributes export-ignore\nPayload/runtime.md export-ignore\n"
    )
    git(repository, "add", ".gitattributes", "Payload/runtime.md")
    git(
      repository,
      "-c", "user.name=PocketRoot Tests",
      "-c", "user.email=tests@pocketroot.invalid",
      "commit", "-q", "-m", "hide payload from source archive"
    )

    error = assert_raises(PocketRootSourceRelease::VerificationError) do
      PocketRootSourceRelease.verify(
        root: repository,
        ref: "HEAD",
        version: "0.1.0"
      )
    end

    assert_includes error.message, "Git archive export filtering is not allowed"
  end

  def test_rejects_release_versions_not_supported_by_compliance_generator
    error = assert_raises(PocketRootSourceRelease::VerificationError) do
      PocketRootSourceRelease.validate_version("0.1.1")
    end

    assert_includes error.message, "bound to source release 0.1.0"
  end

  def test_rejects_compressed_payload_even_under_neutral_path
    archive = source_archive(
      "Payload/input.bin" => "\x1f\x8b\x08unreviewed-rootfs".b
    )

    error = assert_raises(PocketRootSourceRelease::VerificationError) do
      PocketRootSourceRelease.audit_archive(archive, "PocketRoot-0.1.0/")
    end

    assert_includes error.message, "forbidden gzip payload"
  end

  def test_rejects_binary_sdk_path
    archive = source_archive(
      "Vendor/libIshKernel.xcframework" => nil,
      "Vendor/libIshKernel.xcframework/Info.plist" => "plist"
    )

    error = assert_raises(PocketRootSourceRelease::VerificationError) do
      PocketRootSourceRelease.audit_archive(archive, "PocketRoot-0.1.0/")
    end

    assert_includes error.message, "forbidden source-release path"
  end

  def test_rejects_uncompressed_tar_under_neutral_path
    buffer = StringIO.new("".b)
    Gem::Package::TarWriter.new(buffer) do |tar|
      tar.add_file_simple("fs/meta.db", 0o644, 4) do |file|
        file.write("data")
      end
    end
    archive = source_archive("Payload/input.bin" => buffer.string)

    error = assert_raises(PocketRootSourceRelease::VerificationError) do
      PocketRootSourceRelease.audit_archive(archive, "PocketRoot-0.1.0/")
    end

    assert_includes error.message, "forbidden tar payload"
  end

  def test_rejects_valid_utf8_binary_payload_under_allowed_extension
    archive = source_archive(
      "Payload/neutral.md" =>
        "%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF\n"
    )

    error = assert_raises(PocketRootSourceRelease::VerificationError) do
      PocketRootSourceRelease.audit_archive(archive, "PocketRoot-0.1.0/")
    end

    assert_includes error.message, "unsupported MIME type \"application/pdf\""
  end

  def test_rejects_git_archive_local_pax_metadata_for_long_rootfs_path
    long_directory = "a" * 160
    archive = source_archive(
      "#{long_directory}/RootFS/etc/passwd" =>
        "root:x:0:0:root:/root:/bin/sh\n"
    )

    error = assert_raises(PocketRootSourceRelease::VerificationError) do
      PocketRootSourceRelease.audit_archive(
        archive,
        "PocketRoot-0.1.0/"
      )
    end

    assert_includes error.message, "local PAX extended paths are not allowed"
  end

  def test_compliance_uses_the_explicit_trusted_tooling_checkout
    candidate = @temporary_directory.join("candidate")
    trusted = @temporary_directory.join("trusted")
    candidate.join("Scripts").mkpath
    trusted.join("Scripts").mkpath
    candidate.join("Scripts/generate-release-compliance.rb").write("exit 0\n")
    trusted.join("Scripts/generate-release-compliance.rb").write("exit 7\n")

    error = assert_raises(PocketRootSourceRelease::VerificationError) do
      PocketRootSourceRelease.run_compliance(
        candidate,
        "--check",
        tooling_root: trusted
      )
    end

    assert_includes error.message, "release compliance --check failed"
  end

  def test_rejects_text_only_rootfs_payload_tree
    archive = source_archive(
      "RootFS/etc/passwd.txt" => "root:x:0:0:root:/root:/bin/sh\n"
    )

    error = assert_raises(PocketRootSourceRelease::VerificationError) do
      PocketRootSourceRelease.audit_archive(archive, "PocketRoot-0.1.0/")
    end

    assert_includes error.message, "forbidden RootFS payload path"
  end

  def test_rejects_rootfs_payload_hidden_below_reviewed_compliance_path
    archive = source_archive(
      "Compliance/RootFS/v0.3.3/etc/passwd.txt" =>
        "root:x:0:0:root:/root:/bin/sh\n"
    )

    error = assert_raises(PocketRootSourceRelease::VerificationError) do
      PocketRootSourceRelease.audit_archive(archive, "PocketRoot-0.1.0/")
    end

    assert_includes error.message, "forbidden RootFS payload path"
  end

  def test_release_document_markers_must_be_actual_markdown_headings
    root = @temporary_directory.join("malformed-documents")
    documents = {
      "CHANGELOG.md" => "This prose mentions ## 0.1.0 - 2026-07-31 only.\n",
      "CHANGELOG.en.md" => "This prose mentions ## 0.1.0 - 2026-07-31 only.\n",
      "Docs/Releases/0.1.0.md" => "This prose mentions # PocketRoot 0.1.0 only.\n",
      "Docs/en/Releases/0.1.0.md" => "This prose mentions # PocketRoot 0.1.0 only.\n"
    }
    documents.each do |relative_path, contents|
      path = root.join(relative_path)
      path.dirname.mkpath
      path.binwrite(contents)
    end

    error = assert_raises(PocketRootSourceRelease::VerificationError) do
      PocketRootSourceRelease.verify_release_documents(root, "0.1.0")
    end

    assert_includes error.message, "does not declare release 0.1.0"
  end

  def test_validates_authorization_from_the_archived_ref
    repository = release_repository(
      version: "0.1.0",
      authorized_version: "0.1.0",
      authorization_status: "blocked"
    )
    blocked_ref = git(repository, "rev-parse", "HEAD")
    decisions_path =
      repository.join("Compliance/Release/RELEASE-DECISIONS.json")
    decisions = JSON.parse(decisions_path.binread)
    decisions["status"] = "source-release-authorized"
    decisions_path.binwrite(JSON.pretty_generate(decisions))
    git(repository, "add", decisions_path.to_s)
    git(
      repository,
      "-c", "user.name=PocketRoot Tests",
      "-c", "user.email=tests@pocketroot.invalid",
      "commit", "-q", "-m", "authorize newer worktree"
    )

    error = assert_raises(PocketRootSourceRelease::VerificationError) do
      PocketRootSourceRelease.verify(
        root: repository,
        ref: blocked_ref,
        version: "0.1.0"
      )
    end

    assert_includes error.message, "not bound to release 0.1.0"
  end

  def test_rejects_non_annotated_release_tag
    repository = @temporary_directory.join("repository")
    repository.mkpath
    system("git", "init", "-q", repository.to_s) or raise "git init failed"
    repository.join("file.txt").write("source")
    system("git", "-C", repository.to_s, "add", "file.txt") or raise "git add failed"
    system(
      "git", "-C", repository.to_s,
      "-c", "user.name=PocketRoot Tests",
      "-c", "user.email=tests@pocketroot.invalid",
      "commit", "-q", "-m", "fixture"
    ) or raise "git commit failed"
    system("git", "-C", repository.to_s, "tag", "v0.1.0") or raise "git tag failed"

    error = assert_raises(PocketRootSourceRelease::VerificationError) do
      PocketRootSourceRelease.verify_annotated_tag(
        repository,
        "HEAD",
        "v0.1.0"
      )
    end

    assert_includes error.message, "must be an annotated tag"
  end

  private

  def release_repository(
    version:,
    authorized_version:,
    authorization_status: "source-release-authorized"
  )
    repository = @temporary_directory.join("release-repository-#{version}")
    repository.mkpath
    PocketRootSourceRelease::REQUIRED_PATHS.each do |relative_path|
      path = repository.join(relative_path)
      path.dirname.mkpath
      contents =
        if relative_path.start_with?("CHANGELOG")
          "## #{version} - 2026-07-31\n"
        else
          "source\n"
        end
      path.binwrite(contents)
    end
    %W[Docs/Releases/#{version}.md Docs/en/Releases/#{version}.md].each do |relative_path|
      path = repository.join(relative_path)
      path.dirname.mkpath
      path.binwrite("# PocketRoot #{version}\n")
    end
    compliance_script = repository.join("Scripts/generate-release-compliance.rb")
    compliance_script.dirname.mkpath
    compliance_script.binwrite("exit(%w[--check --require-source-ready].include?(ARGV.first) ? 0 : 2)\n")
    readiness = {
      "releaseVersion" => authorized_version,
      "tracks" => {"sourcePackageRelease" => {"status" => "ready"}}
    }
    readiness_path = repository.join(
      "Compliance/Release/experimental-v#{version}/READINESS.json"
    )
    readiness_path.dirname.mkpath
    readiness_path.binwrite(JSON.pretty_generate(readiness))
    decisions_path =
      repository.join("Compliance/Release/RELEASE-DECISIONS.json")
    decisions_path.dirname.mkpath
    decisions_path.binwrite(
      JSON.pretty_generate(
        "releaseVersion" => authorized_version,
        "status" => authorization_status
      )
    )
    system("git", "init", "-q", repository.to_s) or raise "git init failed"
    git(repository, "add", ".")
    git(
      repository,
      "-c", "user.name=PocketRoot Tests",
      "-c", "user.email=tests@pocketroot.invalid",
      "commit", "-q", "-m", "release fixture"
    )
    repository
  end

  def git(repository, *arguments)
    output, status = Open3.capture2e("git", "-C", repository.to_s, *arguments)
    raise "git #{arguments.join(' ')} failed: #{output}" unless status.success?

    output.strip
  end

  def source_archive(extra_entries)
    repository = @temporary_directory.join("archive-repository")
    repository.mkpath
    required = PocketRootSourceRelease::REQUIRED_PATHS.to_h do |path|
      [path, "source\n"]
    end
    (required.merge(extra_entries)).each do |relative_path, contents|
      path = repository.join(relative_path)
      if contents.nil?
        path.mkpath
      else
        path.dirname.mkpath
        path.binwrite(contents)
      end
    end
    system("git", "init", "-q", repository.to_s) or raise "git init failed"
    system("git", "-C", repository.to_s, "add", ".") or raise "git add failed"
    system(
      "git", "-C", repository.to_s,
      "-c", "user.name=PocketRoot Tests",
      "-c", "user.email=tests@pocketroot.invalid",
      "commit", "-q", "-m", "fixture"
    ) or raise "git commit failed"
    archive = @temporary_directory.join("fixture-#{extra_entries.hash}.tar")
    system(
      "git", "-C", repository.to_s,
      "archive", "--format=tar", "--prefix=PocketRoot-0.1.0/",
      "--output=#{archive}", "HEAD"
    ) or raise "git archive failed"
    archive
  end
end
