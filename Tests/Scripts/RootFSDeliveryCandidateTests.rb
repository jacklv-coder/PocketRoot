#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"
require_relative "../../Scripts/prepare-rootfs-delivery-candidate"

class RootFSDeliveryCandidateTests < Minitest::Test
  REPOSITORY_ROOT = Pathname(__dir__).join("../..").realpath
  EVIDENCE_DIRECTORY = REPOSITORY_ROOT.join("Compliance/RootFS/v0.3.3")

  def setup
    @temporary_directory =
      Pathname(Dir.mktmpdir("pocketroot-delivery-candidate-test-"))
  end

  def teardown
    FileUtils.remove_entry(@temporary_directory) if @temporary_directory.exist?
  end

  def test_checked_in_manifests_validate_with_all_approval_gates_closed
    validated =
      RootFSDeliveryCandidate.validate_documents(load_checked_in_documents)

    assert_equal 5, validated.fetch(:units).length
    coverage = validated.fetch(:inventory).fetch("coverage")
    refute coverage.fetch("sourceOfferPrepared")
    refute coverage.fetch("deliveryMechanismApproved")
    refute coverage.fetch("legalReviewApproved")
    refute coverage.fetch("redistributionApproved")
  end

  def test_manifest_validation_rejects_authorization_drift
    documents = load_checked_in_documents
    inventory =
      JSON.parse(
        documents.fetch("SOURCE-DELIVERY-INVENTORY.json").fetch(:contents)
      )
    inventory["coverage"]["sourceOfferPrepared"] = true
    documents["SOURCE-DELIVERY-INVENTORY.json"] =
      documents.fetch("SOURCE-DELIVERY-INVENTORY.json").merge(
        document: inventory,
        contents: RootFSDeliveryCandidate.pretty_json(inventory)
      )

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.validate_documents(documents)
    end

    assert_includes error.message, "not reproducible"
  end

  def test_manifest_validation_requires_current_materializer_readiness
    documents = load_checked_in_documents
    inventory_filename = "SOURCE-DELIVERY-INVENTORY.json"
    inventory =
      JSON.parse(documents.fetch(inventory_filename).fetch(:contents))
    inventory.fetch("coverage")["deliveryCandidateMaterializerReady"] = false
    documents[inventory_filename] =
      documents.fetch(inventory_filename).merge(document: inventory)

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.validate_documents(documents)
    end

    assert_includes error.message, "current materializer ready"
  end

  def test_manifest_validation_binds_builder_source_to_rebuild_evidence
    documents = load_checked_in_documents
    inventory_filename = "SOURCE-DELIVERY-INVENTORY.json"
    inventory =
      JSON.parse(documents.fetch(inventory_filename).fetch(:contents))
    inventory.fetch("deliveryUnits").fetch(0).fetch("source")["revision"] =
      "0" * 40
    documents[inventory_filename] =
      documents.fetch(inventory_filename).merge(document: inventory)

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.validate_documents(documents)
    end

    assert_includes error.message, "does not match rebuild evidence"
  end

  def test_manifest_validation_rejects_modification_disclosure_drift
    documents = load_checked_in_documents
    inventory_filename = "SOURCE-DELIVERY-INVENTORY.json"
    inventory =
      JSON.parse(documents.fetch(inventory_filename).fetch(:contents))
    inventory
      .fetch("deliveryUnits")
      .find { |unit| unit.fetch("id") == "rootfs-modifications" }
      .fetch("items")
      .replace(["inaccurate modification"])
    contents = RootFSDeliveryCandidate.pretty_json(inventory)
    documents[inventory_filename] =
      documents.fetch(inventory_filename).merge(
        document: inventory,
        contents: contents
      )

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.validate_documents(documents)
    end

    assert_includes error.message, "not reproducible"
  end

  def test_manifest_validation_rejects_license_notice_review_result_drift
    documents = load_checked_in_documents
    filename = "LICENSE-NOTICE-REVIEW-RESULTS.json"
    results = JSON.parse(documents.fetch(filename).fetch(:contents))
    results["legalReviewApproved"] = true
    documents[filename] =
      documents.fetch(filename).merge(
        document: results,
        contents: RootFSDeliveryCandidate.pretty_json(results)
      )

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.validate_documents(documents)
    end

    assert_includes error.message, "LICENSE/NOTICE review results"
  end

  def test_manifest_validation_rejects_corresponding_source_review_drift
    documents = load_checked_in_documents
    filename = "CORRESPONDING-SOURCE-REVIEW-RESULTS.json"
    results = JSON.parse(documents.fetch(filename).fetch(:contents))
    results["engineeringReviewCompleted"] = false
    contents = RootFSDeliveryCandidate.pretty_json(results)
    documents[filename] =
      documents.fetch(filename).merge(document: results, contents: contents)
    inventory_filename = "SOURCE-DELIVERY-INVENTORY.json"
    inventory =
      JSON.parse(documents.fetch(inventory_filename).fetch(:contents))
    inventory.fetch("inputEvidence").fetch(filename)["sha256"] =
      RootFSDeliveryCandidate.sha256(contents)
    documents[inventory_filename] =
      documents.fetch(inventory_filename).merge(
        document: inventory,
        contents: RootFSDeliveryCandidate.pretty_json(inventory)
      )

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.validate_documents(documents)
    end

    assert_includes error.message, "corresponding-source review results"
  end

  def test_recursive_git_export_preserves_blobs_modes_symlinks_and_submodule
    fixture = git_fixture
    output = @temporary_directory.join("export")
    output.mkpath

    repositories =
      RootFSDeliveryCandidate.export_git_archives(
        fixture.fetch(:parent),
        fixture.fetch(:parent_revision),
        output,
        repository_path: "."
      )
    export = {
      "revision" => fixture.fetch(:parent_revision),
      "tree" =>
        git(
          fixture.fetch(:parent),
          "rev-parse",
          "#{fixture.fetch(:parent_revision)}^{tree}"
        ).strip,
      "nestedIshRevision" => fixture.fetch(:child_revision),
      "repositoryCount" => repositories.length,
      "entryCount" =>
        repositories.sum { |repository| repository.fetch("entries").length },
      "repositories" => repositories
    }
    source = {
      "tree" => export.fetch("tree"),
      "nestedIshPath" => "deps/child",
      "nestedIshRevision" => fixture.fetch(:child_revision),
      "buildScriptPath" => "scripts/build-rootfs.sh",
      "buildScriptSHA256" =>
        Digest::SHA256.file(
          fixture.fetch(:parent).join("scripts/build-rootfs.sh")
        ).hexdigest
    }

    RootFSDeliveryCandidate.verify_git_export(
      output,
      export,
      source
    )

    assert_equal 2, repositories.length
    assert output.join(
      "git-source-archives/#{fixture.fetch(:parent_revision)}.tar"
    ).file?
    child_repository =
      repositories.find { |repository| repository["repositoryPath"] == "deps/child" }
    assert child_repository
    assert output.join(child_repository.fetch("archivePath")).file?
    assert child_repository.fetch("entries").any? do |entry|
      entry["path"] == "nested.txt" && entry["type"] == "blob"
    end
    root_repository =
      repositories.find { |repository| repository["repositoryPath"] == "." }
    assert_equal root_repository.fetch("tree"),
      RootFSDeliveryCandidate.git_tree_digest(
        root_repository.fetch("entries")
      )

    second_output = @temporary_directory.join("second-export")
    second_output.mkpath
    second_repositories =
      RootFSDeliveryCandidate.export_git_archives(
        fixture.fetch(:parent),
        fixture.fetch(:parent_revision),
        second_output,
        repository_path: "."
      )
    assert_equal repositories, second_repositories
    repositories.each do |repository|
      relative = repository.fetch("archivePath")
      assert_equal Digest::SHA256.file(output.join(relative)).hexdigest,
        Digest::SHA256.file(second_output.join(relative)).hexdigest
    end

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.verify_git_export(
        output,
        export,
        source.merge("nestedIshPath" => "deps/missing")
      )
    end
    assert_includes error.message, "nested iSH gitlink"
  end

  def test_git_archive_preserves_case_distinct_paths_without_materializing_them
    repository = @temporary_directory.join("case-distinct")
    initialize_git_repository(repository)
    upper = hash_git_blob(repository, "upper\n")
    lower = hash_git_blob(repository, "lower\n")
    git(
      repository,
      "update-index",
      "--add",
      "--cacheinfo",
      "100644,#{upper},include/Case.h"
    )
    git(
      repository,
      "update-index",
      "--add",
      "--cacheinfo",
      "100644,#{lower},include/case.h"
    )
    git(repository, "commit", "-m", "case-distinct source")
    revision = git(repository, "rev-parse", "HEAD").strip
    output = @temporary_directory.join("case-distinct-export")
    output.mkpath

    repositories =
      RootFSDeliveryCandidate.export_git_archives(
        repository,
        revision,
        output,
        repository_path: "."
      )
    root = repositories.fetch(0)
    digests =
      RootFSDeliveryCandidate.verify_git_archive(
        output.join(root.fetch("archivePath")),
        root.fetch("entries")
      )

    assert_equal Digest::SHA256.hexdigest("upper\n"),
      digests.fetch("include/Case.h")
    assert_equal Digest::SHA256.hexdigest("lower\n"),
      digests.fetch("include/case.h")
  end

  def test_git_tree_digest_handles_nested_entry_named_path
    repository = @temporary_directory.join("nested-path-entry")
    initialize_git_repository(repository)
    repository.join("foo").mkpath
    repository.join("foo/path").binwrite("valid nested entry\n")
    git(repository, "add", "foo/path")
    git(repository, "commit", "-m", "nested path entry")
    revision = git(repository, "rev-parse", "HEAD").strip
    expected_tree =
      git(repository, "rev-parse", "#{revision}^{tree}").strip
    entries = RootFSDeliveryCandidate.parse_git_tree(repository, revision)

    assert_equal expected_tree,
      RootFSDeliveryCandidate.git_tree_digest(
        entries,
        object_length: revision.length
      )
  end

  def test_git_archive_verifier_accepts_non_ascii_utf8_paths
    repository = @temporary_directory.join("non-ascii-path")
    initialize_git_repository(repository)
    path = "文档/说明.txt"
    repository.join("文档").mkpath
    repository.join(path).binwrite("source\n")
    git(repository, "add", path)
    git(repository, "commit", "-m", "non-ASCII path")
    revision = git(repository, "rev-parse", "HEAD").strip
    output = @temporary_directory.join("non-ascii-path-export")
    output.mkpath
    root =
      RootFSDeliveryCandidate.export_git_archives(
        repository,
        revision,
        output,
        repository_path: "."
      ).fetch(0)

    digests =
      RootFSDeliveryCandidate.verify_git_archive(
        output.join(root.fetch("archivePath")),
        root.fetch("entries")
      )

    assert_equal Digest::SHA256.hexdigest("source\n"), digests.fetch(path.b)
  end

  def test_git_archive_preserves_long_symlink_targets
    repository = @temporary_directory.join("long-symlink")
    initialize_git_repository(repository)
    target = "../#{"segment-" * 24}target"
    repository.join("link").make_symlink(target)
    git(repository, "add", "link")
    git(repository, "commit", "-m", "long symlink")
    revision = git(repository, "rev-parse", "HEAD").strip
    output = @temporary_directory.join("long-symlink-export")
    output.mkpath

    root =
      RootFSDeliveryCandidate.export_git_archives(
        repository,
        revision,
        output,
        repository_path: "."
      ).fetch(0)
    digests =
      RootFSDeliveryCandidate.verify_git_archive(
        output.join(root.fetch("archivePath")),
        root.fetch("entries")
      )

    assert_equal Digest::SHA256.hexdigest(target), digests.fetch("link")
  end

  def test_git_archive_preserves_empty_symlink_targets
    repository = @temporary_directory.join("empty-symlink")
    initialize_git_repository(repository)
    empty_target_blob = hash_git_blob(repository, "")
    git(
      repository,
      "update-index",
      "--add",
      "--cacheinfo",
      "120000,#{empty_target_blob},empty-link"
    )
    git(repository, "commit", "-m", "empty symlink")
    revision = git(repository, "rev-parse", "HEAD").strip
    output = @temporary_directory.join("empty-symlink-export")
    output.mkpath

    root =
      RootFSDeliveryCandidate.export_git_archives(
        repository,
        revision,
        output,
        repository_path: "."
      ).fetch(0)
    digests =
      RootFSDeliveryCandidate.verify_git_archive(
        output.join(root.fetch("archivePath")),
        root.fetch("entries")
      )

    assert_equal Digest::SHA256.hexdigest(""), digests.fetch("empty-link")
  end

  def test_git_archive_preserves_paths_beyond_ustar_name_limits
    repository = @temporary_directory.join("long-path")
    initialize_git_repository(repository)
    contents = "long path\n"
    object = hash_git_blob(repository, contents)
    path = "#{"directory-" * 12}/#{"filename-" * 14}.txt"
    git(
      repository,
      "update-index",
      "--add",
      "--cacheinfo",
      "100644,#{object},#{path}"
    )
    git(repository, "commit", "-m", "long path")
    revision = git(repository, "rev-parse", "HEAD").strip
    output = @temporary_directory.join("long-path-export")
    output.mkpath

    root =
      RootFSDeliveryCandidate.export_git_archives(
        repository,
        revision,
        output,
        repository_path: "."
      ).fetch(0)
    digests =
      RootFSDeliveryCandidate.verify_git_archive(
        output.join(root.fetch("archivePath")),
        root.fetch("entries")
      )

    assert_equal Digest::SHA256.hexdigest(contents), digests.fetch(path)
  end

  def test_git_archive_rejects_nonempty_symlink_payload
    archive = @temporary_directory.join("malformed-symlink.tar")
    target = "target"
    object =
      Digest::SHA1.hexdigest("blob #{target.bytesize}\0#{target}")
    File.open(archive, "wb") do |file|
      file.write(
        Gem::Package::TarHeader.new(
          name: "link",
          prefix: "",
          mode: 0o777,
          size: 3,
          typeflag: "2",
          linkname: target,
          mtime: Time.at(0).utc
        ).to_s
      )
      file.write("bad")
      file.write("\0" * 509)
      file.write("\0" * 1_024)
    end

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.verify_git_archive(
        archive,
        [
          {
            "path" => "link",
            "mode" => "120000",
            "type" => "blob",
            "object" => object
          }
        ]
      )
    end

    assert_includes error.message, "symlink mode mismatch"
  end

  def test_git_archive_rejects_directory_payload
    archive = @temporary_directory.join("directory-payload.tar")
    contents = "payload\n"
    object =
      Digest::SHA1.hexdigest("blob #{contents.bytesize}\0#{contents}")
    File.open(archive, "wb") do |file|
      file.write(
        Gem::Package::TarHeader.new(
          name: "directory",
          prefix: "",
          mode: 0o755,
          size: 3,
          typeflag: "5",
          mtime: Time.at(0).utc
        ).to_s
      )
      file.write("bad")
      file.write("\0" * 509)
      file.write(
        Gem::Package::TarHeader.new(
          name: "directory/payload",
          prefix: "",
          mode: 0o644,
          size: contents.bytesize,
          typeflag: "0",
          mtime: Time.at(0).utc
        ).to_s
      )
      file.write(contents)
      file.write("\0" * ((512 - (contents.bytesize % 512)) % 512))
      file.write("\0" * 1_024)
    end

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.verify_git_archive(
        archive,
        [
          {
            "path" => "directory/payload",
            "mode" => "100644",
            "type" => "blob",
            "object" => object
          }
        ]
      )
    end

    assert_includes error.message, "directory"
  end

  def test_git_export_allows_one_archive_for_repeated_gitlinks
    child = @temporary_directory.join("shared-child")
    initialize_git_repository(child)
    child.join("payload").binwrite("shared\n")
    git(child, "add", "payload")
    git(child, "commit", "-m", "shared child")
    child_revision = git(child, "rev-parse", "HEAD").strip

    parent = @temporary_directory.join("shared-parent")
    initialize_git_repository(parent)
    parent.join("README").binwrite("parent\n")
    git(parent, "add", "README")
    git(parent, "commit", "-m", "parent")
    %w[first second].each do |path|
      git(
        parent,
        "update-index",
        "--add",
        "--cacheinfo",
        "160000,#{child_revision},#{path}"
      )
    end
    git(parent, "commit", "-m", "repeat child")
    FileUtils.cp_r(child.to_s, parent.join("first").to_s)
    FileUtils.cp_r(child.to_s, parent.join("second").to_s)
    parent_revision = git(parent, "rev-parse", "HEAD").strip
    output = @temporary_directory.join("shared-export")
    output.mkpath
    repositories =
      RootFSDeliveryCandidate.export_git_archives(
        parent,
        parent_revision,
        output,
        repository_path: "."
      )
    root = repositories.find { |repository| repository["repositoryPath"] == "." }
    export = {
      "revision" => parent_revision,
      "tree" => root.fetch("tree"),
      "repositoryCount" => repositories.length,
      "entryCount" =>
        repositories.sum { |repository| repository.fetch("entries").length },
      "repositories" => repositories
    }

    RootFSDeliveryCandidate.verify_git_export(
      output,
      export,
      {"tree" => root.fetch("tree")}
    )

    children =
      repositories.reject { |repository| repository["repositoryPath"] == "." }
    assert_equal 2, children.length
    assert_equal 1, children.map { |repository| repository["archivePath"] }.uniq.length
  end

  def test_recursive_git_export_rejects_uninitialized_submodule
    fixture = git_fixture
    FileUtils.remove_entry(fixture.fetch(:parent).join("deps/child"))

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.export_git_archives(
        fixture.fetch(:parent),
        fixture.fetch(:parent_revision),
        @temporary_directory.join("missing-submodule-export"),
        repository_path: "."
      )
    end

    assert_includes error.message, "not initialized"
  end

  def test_git_export_verifier_rejects_payload_tampering
    fixture = git_fixture
    output = @temporary_directory.join("export")
    output.mkpath
    repositories =
      RootFSDeliveryCandidate.export_git_archives(
        fixture.fetch(:parent),
        fixture.fetch(:parent_revision),
        output,
        repository_path: "."
      )
    root_repository =
      repositories.find { |repository| repository["repositoryPath"] == "." }
    archive = output.join(root_repository.fetch("archivePath"))
    bytes = archive.binread
    assert_includes bytes, "readme\n"
    archive.binwrite(bytes.sub("readme\n", "xxxxxx\n"))
    export = {
      "revision" => fixture.fetch(:parent_revision),
      "tree" =>
        git(
          fixture.fetch(:parent),
          "rev-parse",
          "#{fixture.fetch(:parent_revision)}^{tree}"
        ).strip,
      "nestedIshRevision" => fixture.fetch(:child_revision),
      "repositoryCount" => repositories.length,
      "entryCount" =>
        repositories.sum { |repository| repository.fetch("entries").length },
      "repositories" => repositories
    }

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.verify_git_export(
        output,
        export,
        {
          "tree" => export.fetch("tree"),
          "buildScriptPath" => "scripts/build-rootfs.sh",
          "buildScriptSHA256" =>
            Digest::SHA256.hexdigest("builder\n")
        }
      )
    end

    assert_match(/archive|checksum|path set|entry/, error.message)
  end

  def test_git_archive_verifier_rejects_bytes_after_end_marker
    fixture = git_fixture
    output = @temporary_directory.join("trailing-data-export")
    output.mkpath
    repositories =
      RootFSDeliveryCandidate.export_git_archives(
        fixture.fetch(:parent),
        fixture.fetch(:parent_revision),
        output,
        repository_path: "."
      )
    root_repository =
      repositories.find { |repository| repository["repositoryPath"] == "." }
    archive = output.join(root_repository.fetch("archivePath"))
    File.open(archive, "ab") { |file| file.write("unbound trailing data") }

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.verify_git_archive(
        archive,
        root_repository.fetch("entries")
      )
    end

    assert_includes error.message, "canonical end-of-archive marker"
  end

  def test_git_archive_verifier_rejects_nonzero_entry_padding
    archive = @temporary_directory.join("nonzero-padding.tar")
    contents = "x"
    object = Digest::SHA1.hexdigest("blob 1\0x")
    File.open(archive, "wb") do |file|
      file.write(
        Gem::Package::TarHeader.new(
          name: "payload",
          prefix: "",
          mode: 0o644,
          size: contents.bytesize,
          typeflag: "0",
          mtime: Time.at(0).utc
        ).to_s
      )
      file.write(contents)
      file.write("!" + ("\0" * 510))
      file.write("\0" * 1_024)
    end

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.verify_git_archive(
        archive,
        [
          {
            "path" => "payload",
            "mode" => "100644",
            "type" => "blob",
            "object" => object
          }
        ]
      )
    end

    assert_includes error.message, "non-zero entry padding"
  end

  def test_git_export_verifier_binds_commit_object_tree_and_pinned_tree
    fixture = git_fixture
    output = @temporary_directory.join("commit-binding-export")
    output.mkpath
    repositories =
      RootFSDeliveryCandidate.export_git_archives(
        fixture.fetch(:parent),
        fixture.fetch(:parent_revision),
        output,
        repository_path: "."
      )
    actual_tree =
      git(
        fixture.fetch(:parent),
        "rev-parse",
        "#{fixture.fetch(:parent_revision)}^{tree}"
      ).strip
    export = {
      "revision" => fixture.fetch(:parent_revision),
      "tree" => actual_tree,
      "nestedIshRevision" => fixture.fetch(:child_revision),
      "repositoryCount" => repositories.length,
      "entryCount" =>
        repositories.sum { |repository| repository.fetch("entries").length },
      "repositories" => repositories
    }

    tampered = JSON.parse(JSON.generate(export))
    tampered_root =
      tampered.fetch("repositories").find do |repository|
        repository["repositoryPath"] == "."
      end
    tampered_root["tree"] = "0" * 40
    tampered["tree"] = "0" * 40
    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.verify_git_export(
        output,
        tampered,
        {"tree" => "0" * 40}
      )
    end
    assert_includes error.message, "commit/tree binding"

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.verify_git_export(
        output,
        export,
        {"tree" => "f" * 40}
      )
    end
    assert_includes error.message, "root archive binding"
  end

  def test_git_archive_verifier_rejects_noncanonical_regular_file_mode
    archive = @temporary_directory.join("wrong-mode.tar")
    previous_epoch = ENV["SOURCE_DATE_EPOCH"]
    ENV["SOURCE_DATE_EPOCH"] = "0"
    File.open(archive, "wb") do |file|
      Gem::Package::TarWriter.new(file) do |tar|
        tar.add_file_simple("payload", 0o600, 8) do |io|
          io.write("payload\n")
        end
      end
    end
    object = Digest::SHA1.hexdigest("blob 8\0payload\n")

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.verify_git_archive(
        archive,
        [
          {
            "path" => "payload",
            "mode" => "100644",
            "type" => "blob",
            "object" => object
          }
        ]
      )
    end

    assert_includes error.message, "mode mismatch"
  ensure
    if previous_epoch.nil?
      ENV.delete("SOURCE_DATE_EPOCH")
    else
      ENV["SOURCE_DATE_EPOCH"] = previous_epoch
    end
  end

  def test_modification_disclosure_must_match_index_exactly
    root = @temporary_directory.join("disclosure")
    root.mkpath
    unit = {"items" => ["first change", "second change"]}
    root.join("MODIFICATIONS.md").binwrite(
      RootFSDeliveryCandidate.modifications_markdown(unit).sub(
        "first change",
        "different change"
      )
    )

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.verify_modification_disclosure(root, unit)
    end

    assert_includes error.message, "does not match its index"
  end

  def test_command_output_enforces_the_limit_while_streaming
    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.command_output(
        [
          RbConfig.ruby,
          "-e",
          "$stdout.sync = true; 16.times { $stdout.write(\"x\" * 1_024) }"
        ],
        "streaming fixture",
        maximum_bytes: 1_024
      )
    end

    assert_includes error.message, "output exceeded the safety limit"
  end

  def test_command_group_termination_tolerates_macos_exit_race
    signaler = Object.new
    signaler.define_singleton_method(:kill) do |signal, _process_group|
      raise Errno::EPERM if signal == "KILL"

      raise Errno::ESRCH
    end
    wait_thread = Struct.new(:pid) do
      def join(_timeout)
        self
      end
    end.new(12_345)

    assert_nil(
      RootFSDeliveryCandidate.terminate_command_group(
        wait_thread,
        signaler: signaler
      )
    )
  end

  def test_command_group_termination_preserves_real_permission_failure
    signaler = Object.new
    signaler.define_singleton_method(:kill) do |signal, _process_group|
      raise Errno::EPERM if signal == "KILL"

      1
    end
    wait_thread = Struct.new(:pid) do
      def join(_timeout)
        nil
      end
    end.new(12_345)

    assert_raises(Errno::EPERM) do
      RootFSDeliveryCandidate.terminate_command_group(
        wait_thread,
        signaler: signaler
      )
    end
  end

  def test_command_group_termination_preserves_unsignalable_descendant
    signaler = Object.new
    signaler.define_singleton_method(:kill) do |_signal, _process_group|
      raise Errno::EPERM
    end
    wait_thread = Struct.new(:pid) do
      def join(_timeout)
        self
      end
    end.new(12_345)

    assert_raises(Errno::EPERM) do
      RootFSDeliveryCandidate.terminate_command_group(
        wait_thread,
        signaler: signaler
      )
    end
  end

  def test_builder_identity_fields_must_match_inventory
    source = {
      "repository" => "owner/repository",
      "revision" => "a" * 40,
      "nestedIshPath" => "third_party/ish",
      "nestedIshRevision" => "b" * 40
    }
    export = source.dup
    export["repository"] = "misleading/repository"

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.verify_builder_inventory_binding(
        export,
        source,
        "historicalRootFSBuilder"
      )
    end

    assert_includes error.message, "repository"
  end

  def test_candidate_documents_are_loaded_from_bundled_evidence
    root = @temporary_directory.join("candidate-evidence")
    evidence = root.join("evidence")
    evidence.mkpath
    RootFSDeliveryCandidate::EVIDENCE_FILES.each do |filename|
      FileUtils.copy_file(
        EVIDENCE_DIRECTORY.join(filename),
        evidence.join(filename)
      )
    end

    documents = RootFSDeliveryCandidate.load_candidate_documents(root)
    RootFSDeliveryCandidate.validate_documents(documents)

    documents.each_value do |input|
      assert input.fetch(:path).to_s.start_with?("#{evidence}/")
    end
  end

  def test_candidate_evidence_is_bound_to_checked_in_canonical_bytes
    root = @temporary_directory.join("candidate-evidence")
    evidence = root.join("evidence")
    evidence.mkpath
    RootFSDeliveryCandidate::EVIDENCE_FILES.each do |filename|
      FileUtils.copy_file(
        EVIDENCE_DIRECTORY.join(filename),
        evidence.join(filename)
      )
    end
    filename = "SOURCE-ACQUISITION.json"
    evidence.join(filename).binwrite(
      "#{evidence.join(filename).binread.rstrip}\n\n"
    )

    candidate_documents =
      RootFSDeliveryCandidate.load_candidate_documents(root)
    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.verify_canonical_evidence(
        candidate_documents,
        load_checked_in_documents
      )
    end

    assert_includes error.message, "checked-in canonical evidence"
    assert_includes error.message, filename
  end

  def test_verify_mode_rejects_an_alternate_evidence_authority
    alternate = @temporary_directory.join("SOURCE-ACQUISITION.json")
    alternate.binwrite("{}\n")

    error = assert_raises(OptionParser::InvalidOption) do
      RootFSDeliveryCandidate.parse_options(
        [
          "--verify",
          @temporary_directory.to_s,
          "--source-manifest",
          alternate.to_s
        ]
      )
    end

    assert_includes error.message, "checked-in canonical RootFS evidence"
  end

  def test_receipt_is_explicitly_unapproved
    documents = load_checked_in_documents
    alpine = @temporary_directory.join("alpine.tar.gz")
    alpine.binwrite("fixture\n")
    receipt =
      RootFSDeliveryCandidate.receipt(
        documents,
        {"schemaVersion" => 1},
        alpine
      )

    assert_equal "rootfs-delivery-candidate-unapproved",
      receipt.fetch("bundleKind")
    assert receipt.fetch("candidateInputsVerified")
    refute receipt.fetch("completeCorrespondingSourceBundlePresent")
    refute receipt.fetch("completeLicenseAndNoticeBundlePresent")
    refute receipt.fetch("sourceOfferPrepared")
    refute receipt.fetch("deliveryMechanismApproved")
    refute receipt.fetch("legalReviewApproved")
    refute receipt.fetch("redistributionApproved")
    refute receipt.fetch("distributionAuthorized")
  end

  def test_receipt_status_and_delivery_units_are_exactly_bound
    documents = load_checked_in_documents
    alpine = @temporary_directory.join("alpine.tar.gz")
    alpine.binwrite("fixture\n")
    source_exports = {"schemaVersion" => 1}
    receipt =
      RootFSDeliveryCandidate.receipt(documents, source_exports, alpine)

    [
      ["status", "misleading-status"],
      [
        "deliveryUnits",
        receipt.fetch("deliveryUnits").merge(
          "historicalRootFSBuilderSourceExported" => false
        )
      ]
    ].each do |key, value|
      mutated = Marshal.load(Marshal.dump(receipt))
      mutated[key] = value
      error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
        RootFSDeliveryCandidate.verify_receipt(
          mutated,
          documents,
          source_exports,
          alpine
        )
      end
      assert_includes error.message, "generated receipt schema"
    end
  end

  def test_tree_manifest_and_checksums_detect_byte_and_mode_drift
    root = @temporary_directory.join("tree")
    root.mkpath
    root.join("file").binwrite("payload\n")
    root.join("file").chmod(0o644)
    original = RootFSDeliveryCandidate.tree_entries(root)
    original_checksums = RootFSDeliveryCandidate.checksum_lines(root)

    root.join("file").chmod(0o600)
    refute_equal original, RootFSDeliveryCandidate.tree_entries(root)
    root.join("file").chmod(0o644)
    root.join("file").binwrite("changed\n")
    refute_equal original_checksums,
      RootFSDeliveryCandidate.checksum_lines(root)
  end

  def test_candidate_file_rejects_symlink_traversal
    root = @temporary_directory.join("candidate")
    outside = @temporary_directory.join("outside")
    root.mkpath
    outside.mkpath
    outside.join("payload").binwrite("outside\n")
    root.join("linked").make_symlink(outside)

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.require_candidate_file(root, "linked/payload")
    end

    assert_includes error.message, "contains a symlink"
  end

  def test_candidate_layout_rejects_unreviewed_content
    root = @temporary_directory.join("candidate-layout")
    root.mkpath
    %w[
      corresponding-source-candidate evidence git-source-archives inputs
      license-notice-candidate license-review-evidence
    ].each { |relative| root.join(relative).mkpath }
    %w[
      DELIVERY-CANDIDATE-RECEIPT.json GIT-SOURCE-EXPORTS.json MODIFICATIONS.md
      SHA256SUMS TREE-MANIFEST.json
    ].each { |relative| root.join(relative).binwrite("") }
    RootFSDeliveryCandidate::EVIDENCE_FILES.each do |filename|
      root.join("evidence", filename).binwrite("")
    end
    %w[a b].each do |revision|
      root.join("git-source-archives", "#{revision}.tar").binwrite("")
    end
    alpine_filename = "alpine-minirootfs.tar.gz"
    root.join("inputs", alpine_filename).binwrite("")
    source_exports = {
      "historicalRootFSBuilder" => {
        "repositories" => [
          {"archivePath" => "git-source-archives/a.tar"}
        ]
      },
      "successorRootFSBuilder" => {
        "repositories" => [
          {"archivePath" => "git-source-archives/b.tar"}
        ]
      }
    }

    RootFSDeliveryCandidate.verify_candidate_layout(
      root,
      source_exports,
      alpine_filename
    )
    root.join("unreviewed.txt").binwrite("extra\n")

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.verify_candidate_layout(
        root,
        source_exports,
        alpine_filename
      )
    end

    assert_includes error.message, "unreviewed content"
  end

  def test_output_must_not_overlap_an_input
    input = @temporary_directory.join("input")
    input.mkpath

    error = assert_raises(RootFSDeliveryCandidate::CandidateError) do
      RootFSDeliveryCandidate.validate_new_output(
        input.join("nested"),
        [input.realpath]
      )
    end

    assert_includes error.message, "must not overlap"
  end

  private

  def load_checked_in_documents
    options = {
      inventory:
        EVIDENCE_DIRECTORY.join("SOURCE-DELIVERY-INVENTORY.json").to_s,
      rebuild_review:
        EVIDENCE_DIRECTORY.join("REBUILD-ENVIRONMENT-REVIEW.json").to_s,
      source_acquisition:
        EVIDENCE_DIRECTORY.join("SOURCE-ACQUISITION.json").to_s,
      source_inventory:
        EVIDENCE_DIRECTORY.join("SOURCE-INVENTORY.json").to_s,
      source_review_results:
        EVIDENCE_DIRECTORY.join(
          "CORRESPONDING-SOURCE-REVIEW-RESULTS.json"
        ).to_s,
      license_candidates:
        EVIDENCE_DIRECTORY.join("LICENSE-NOTICE-CANDIDATES.json").to_s,
      license_notice_review_results:
        EVIDENCE_DIRECTORY.join(
          "LICENSE-NOTICE-REVIEW-RESULTS.json"
        ).to_s,
      license_review_results:
        EVIDENCE_DIRECTORY.join("LICENSE-REVIEW-RESULTS.json").to_s,
      license_review:
        EVIDENCE_DIRECTORY.join("LICENSE-REVIEW.json").to_s
    }
    RootFSDeliveryCandidate.load_documents(options)
  end

  def git_fixture
    child = @temporary_directory.join("child")
    initialize_git_repository(child)
    child.join("nested.txt").binwrite("nested\n")
    git(child, "add", "nested.txt")
    git(child, "commit", "-m", "child")
    child_revision = git(child, "rev-parse", "HEAD").strip

    parent = @temporary_directory.join("parent")
    initialize_git_repository(parent)
    parent.join("scripts").mkpath
    parent.join("links").mkpath
    parent.join("README.md").binwrite("readme\n")
    parent.join("scripts/build-rootfs.sh").binwrite("builder\n")
    parent.join("scripts/build-rootfs.sh").chmod(0o755)
    parent.join("links/readme").make_symlink("../README.md")
    git(parent, "add", "README.md", "scripts/build-rootfs.sh", "links/readme")
    git(parent, "commit", "-m", "parent files")
    git(
      parent,
      "update-index",
      "--add",
      "--cacheinfo",
      "160000,#{child_revision},deps/child"
    )
    git(parent, "commit", "-m", "pin child")
    parent.join("deps").mkpath
    FileUtils.cp_r(child.to_s, parent.join("deps/child").to_s)
    {
      parent: parent,
      parent_revision: git(parent, "rev-parse", "HEAD").strip,
      child_revision: child_revision
    }
  end

  def initialize_git_repository(path)
    path.mkpath
    git(path, "init", "-q")
    git(path, "config", "user.name", "PocketRoot Tests")
    git(path, "config", "user.email", "tests@example.invalid")
  end

  def git(path, *arguments)
    stdout, stderr, status =
      Open3.capture3("git", "-C", path.to_s, *arguments)
    assert status.success?, "#{arguments.join(" ")}\n#{stdout}\n#{stderr}"
    stdout
  end

  def hash_git_blob(repository, contents)
    stdout, stderr, status =
      Open3.capture3(
        "git",
        "-C",
        repository.to_s,
        "hash-object",
        "-w",
        "--stdin",
        stdin_data: contents
      )
    assert status.success?, "#{stdout}\n#{stderr}"
    stdout.strip
  end
end
