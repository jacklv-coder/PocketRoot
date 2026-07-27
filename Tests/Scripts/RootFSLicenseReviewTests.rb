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

class RootFSLicenseReviewTests < Minitest::Test
  REPOSITORY_ROOT = Pathname(__dir__).join("../..").realpath
  SOURCE_SCRIPT =
    REPOSITORY_ROOT.join("Scripts/prepare-rootfs-source-bundle.rb")
  REVIEW_SCRIPT =
    REPOSITORY_ROOT.join("Scripts/prepare-rootfs-license-review.rb")
  ROOTFS_SHA256 =
    "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
  COMMIT = "0123456789abcdef0123456789abcdef01234567"

  def setup
    @temporary_directory = Pathname(Dir.mktmpdir("pocketroot-license-review-test-"))
    @snapshot = @temporary_directory.join("demo-snapshot.tar.gz")
    @distfile = @temporary_directory.join("demo-source.tar.gz")
    @license_contents = "Demo license text\n"
    write_tar_gz(
      @snapshot,
      {"snapshot/main/demo/APKBUILD" => "pkgname=demo\nlicense=MIT\n"}
    )
    write_tar_gz(
      @distfile,
      {"demo-source/LICENSE" => @license_contents}
    )
    @source_manifest_path = @temporary_directory.join("source-manifest.json")
    @source_inventory_path = @temporary_directory.join("source-inventory.json")
    @corresponding_source_review_results_path =
      @temporary_directory.join(
        "corresponding-source-review-results.json"
      )
    @review_manifest_path = @temporary_directory.join("license-review.json")
    write_fixture_documents
    @source_bundle = @temporary_directory.join("source-bundle")
    stdout, stderr, status = run_source("--output", @source_bundle.to_s)
    assert status.success?, "#{stdout}\n#{stderr}"
  end

  def teardown
    FileUtils.remove_entry(@temporary_directory) if @temporary_directory.exist?
  end

  def test_materializes_and_verifies_external_candidate_review
    output = @temporary_directory.join("license-review-output")
    stdout, stderr, status = run_review("--output", output.to_s)

    assert status.success?, "#{stdout}\n#{stderr}"
    assert_includes stdout, "Materialized RootFS license/NOTICE candidate review"
    assert_equal @license_contents,
      output.join("evidence/demo/LICENSE").binread
    assert_equal "pkgname=demo\nlicense=MIT\n",
      output.join("evidence/demo/APKBUILD").binread
    assert output.join("LICENSE-REVIEW.json").file?
    assert output.join("NOTICE.md").file?
    assert output.join("REVIEW-RECEIPT.json").file?
    assert output.join("SHA256SUMS").file?

    verify_stdout, verify_stderr, verify_status =
      run_review("--verify", output.to_s)
    assert verify_status.success?, "#{verify_stdout}\n#{verify_stderr}"
    assert_includes verify_stdout,
      "Verified RootFS license/NOTICE candidate review"
  end

  def test_verification_rejects_tampered_candidate
    output = @temporary_directory.join("tampered-output")
    _stdout, stderr, status = run_review("--output", output.to_s)
    assert status.success?, stderr
    output.join("evidence/demo/LICENSE").binwrite("changed\n")

    _verify_stdout, verify_stderr, verify_status =
      run_review("--verify", output.to_s)

    refute verify_status.success?
    assert_includes verify_stderr,
      "license-review file does not match pinned bytes"
  end

  def test_verification_rejects_extra_file
    output = @temporary_directory.join("extra-output")
    _stdout, stderr, status = run_review("--output", output.to_s)
    assert status.success?, stderr
    output.join("extra.txt").binwrite("extra\n")

    _verify_stdout, verify_stderr, verify_status =
      run_review("--verify", output.to_s)

    refute verify_status.success?
    assert_includes verify_stderr,
      "path/type set does not match pinned candidates"
  end

  def test_verification_rejects_extra_empty_directory
    output = @temporary_directory.join("extra-directory-output")
    _stdout, stderr, status = run_review("--output", output.to_s)
    assert status.success?, stderr
    output.join("empty-extra").mkpath

    _verify_stdout, verify_stderr, verify_status =
      run_review("--verify", output.to_s)

    refute verify_status.success?
    assert_includes verify_stderr,
      "path/type set does not match pinned candidates"
  end

  def test_requires_explicit_fixture_file_url_gate
    output = @temporary_directory.join("no-fixture-gate-output")
    _stdout, stderr, status =
      run_review("--output", output.to_s, allow_file_urls: false)

    refute status.success?
    assert_includes stderr, "aportsSnapshot.url must use https"
    refute output.exist?
  end

  def test_rejects_output_nested_inside_source_bundle
    output = @source_bundle.join("license-review-output")

    _stdout, stderr, status = run_review("--output", output.to_s)

    refute status.success?
    assert_includes stderr, "--output must be outside --source-bundle"
    refute output.exist?
    verify_stdout, verify_stderr, verify_status =
      run_source("--verify", @source_bundle.to_s)
    assert verify_status.success?, "#{verify_stdout}\n#{verify_stderr}"
  end

  def test_validate_only_rejects_missing_source_origin
    review = JSON.parse(@review_manifest_path.read)
    review["sources"] = []
    @review_manifest_path.write("#{JSON.pretty_generate(review)}\n")

    _stdout, stderr, status = run_review("--validate-only")

    refute status.success?
    assert_includes stderr, "must cover every source origin exactly"
  end

  def test_validate_only_rejects_unsafe_archive_member
    review = JSON.parse(@review_manifest_path.read)
    candidate = review.fetch("sources").first.fetch("candidateEvidence").find do |entry|
      entry.fetch("sourceKind") == "distfile-member"
    end
    candidate["member"] = "../LICENSE"
    @review_manifest_path.write("#{JSON.pretty_generate(review)}\n")

    _stdout, stderr, status = run_review("--validate-only")

    refute status.success?
    assert_includes stderr, "unsafe archive member"
  end

  def test_validate_only_rejects_malformed_source_review_results
    @corresponding_source_review_results_path.binwrite("not json\n")

    _stdout, stderr, status = run_review("--validate-only")

    refute status.success?
    assert_includes stderr,
      "corresponding-source review results is invalid JSON"
  end

  private

  def write_tar_gz(destination, files)
    Zlib::GzipWriter.open(destination.to_s) do |gzip|
      Gem::Package::TarWriter.new(gzip) do |tar|
        files.each do |name, contents|
          tar.add_file_simple(name, 0o644, contents.bytesize) do |entry|
            entry.write(contents)
          end
        end
      end
    end
  end

  def file_url(path)
    "file://#{path}"
  end

  def canonical_tree_digest(relative_path, contents)
    digest = Digest::SHA256.hexdigest(contents)
    Digest::SHA256.hexdigest(
      "file\0#{relative_path}\0" \
      "0644\0#{digest}\0"
    )
  end

  def write_fixture_documents
    archive = {
      "version" => "v0.3.3",
      "sha256" => ROOTFS_SHA256
    }
    inventory = {
      "schemaVersion" => 1,
      "archive" => archive,
      "completeCorrespondingSourceBundlePresent" => false,
      "correspondingSourceCandidateEngineeringReviewCompleted" => true,
      "candidateBundleMaterializerReady" => true,
      "rebuildEnvironmentVerified" => false,
      "correspondingSourceDeliveryApproved" => false,
      "status" =>
        "candidate-material-engineering-reviewed-external-bundle-required",
      "sourceOrigins" => [
        {
          "sourceOrigin" => "demo",
          "aportsCommit" => COMMIT,
          "binaryPackages" => ["demo"],
          "declaredLicenseExpressions" => ["MIT"],
          "containsDeclaredCopyleft" => false,
          "correspondingSourceStatus" =>
            "candidate-material-engineering-reviewed-external-bundle-required"
        }
      ]
    }
    apkbuild = "pkgname=demo\nlicense=MIT\n"
    source_manifest = {
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
              canonical_tree_digest("main/demo/APKBUILD", apkbuild)
          },
          "distfiles" => [
            {
              "filename" => "demo-source.tar.gz",
              "retrievalURLs" => [file_url(@distfile)],
              "sha512" => Digest::SHA512.file(@distfile).hexdigest
            }
          ]
        }
      ]
    }
    source_bytes = "#{JSON.pretty_generate(source_manifest)}\n"
    corresponding_source_review_results = {
      "schemaVersion" => 1,
      "archive" => archive,
      "sourceAcquisitionSha256" => Digest::SHA256.hexdigest(source_bytes),
      "status" =>
        "candidate-corresponding-source-material-engineering-reviewed-open-release-gates",
      "engineeringReviewCompleted" => true,
      "allSourceOriginsReviewed" => true,
      "completeCandidateSourceMaterialIndexPresent" => true,
      "candidateBundleMaterializerReady" => true,
      "completeCorrespondingSourceBundlePresent" => false,
      "rebuildEnvironmentVerified" => false,
      "correspondingSourceDeliveryApproved" => false,
      "legalReviewApproved" => false,
      "redistributionApproved" => false,
      "reviewedSourceOriginCount" => 1,
      "reviewedCanonicalAportsEntryCount" => 1,
      "reviewedDistfileCount" => 1,
      "sourceOriginsWithRemainingMaterialItems" => 0,
      "sources" => [
        {
          "sourceOrigin" => "demo",
          "aportsCommit" => COMMIT,
          "binaryPackages" => ["demo"],
          "declaredLicenseExpressions" => ["MIT"],
          "containsDeclaredCopyleft" => false,
          "reviewedCanonicalAportsEntryCount" => 1,
          "reviewedDistfileCount" => 1,
          "materialCoverage" => "complete",
          "reviewState" =>
            "candidate-source-material-engineering-reviewed-delivery-approval-open",
          "resolvedReviewItems" => [
            "bind-source-material-to-installed-binaries",
            "pin-complete-aports-recipe-tree",
            "pin-declared-upstream-distfiles"
          ],
          "remainingReviewItems" => [],
          "engineeringConclusion" =>
            "candidate-source-material-complete-engineering-only"
        }
      ]
    }
    review_manifest = {
      "schemaVersion" => 1,
      "archive" => archive,
      "sourceAcquisitionSha256" => Digest::SHA256.hexdigest(source_bytes),
      "status" => "candidate-evidence-indexed-external-review-required",
      "completeLicenseTextBundlePresent" => false,
      "completePackageNoticeSetPresent" => false,
      "legalReviewApproved" => false,
      "redistributionApproved" => false,
      "sources" => [
        {
          "sourceOrigin" => "demo",
          "binaryPackages" => ["demo"],
          "declaredLicenseExpressions" => ["MIT"],
          "reviewState" => "engineering-indexed-legal-review-open",
          "candidateEvidence" => [
            {
              "sourceKind" => "aports-file",
              "path" => "aports/demo/APKBUILD",
              "outputPath" => "evidence/demo/APKBUILD",
              "byteCount" => apkbuild.bytesize,
              "sha256" => Digest::SHA256.hexdigest(apkbuild),
              "evidenceKinds" => ["license-declaration"],
              "reviewState" => "unreviewed-candidate"
            },
            {
              "sourceKind" => "distfile-member",
              "distfile" => "demo-source.tar.gz",
              "member" => "demo-source/LICENSE",
              "outputPath" => "evidence/demo/LICENSE",
              "byteCount" => @license_contents.bytesize,
              "sha256" => Digest::SHA256.hexdigest(@license_contents),
              "evidenceKinds" => ["license-text"],
              "reviewState" => "unreviewed-candidate"
            }
          ],
          "openReviewItems" => [
            "confirm-package-specific-attribution"
          ]
        }
      ]
    }

    @source_inventory_path.write("#{JSON.pretty_generate(inventory)}\n")
    @source_manifest_path.binwrite(source_bytes)
    @corresponding_source_review_results_path.write(
      "#{JSON.pretty_generate(corresponding_source_review_results)}\n"
    )
    @review_manifest_path.write("#{JSON.pretty_generate(review_manifest)}\n")
  end

  def run_source(*arguments)
    Open3.capture3(
      {"POCKETROOT_TEST_ALLOW_FILE_URLS" => "1"},
      RbConfig.ruby,
      SOURCE_SCRIPT.to_s,
      "--manifest", @source_manifest_path.to_s,
      "--source-inventory", @source_inventory_path.to_s,
      "--review-results",
      @corresponding_source_review_results_path.to_s,
      *arguments,
      chdir: REPOSITORY_ROOT.to_s
    )
  end

  def run_review(*arguments, allow_file_urls: true)
    environment = {}
    environment["POCKETROOT_TEST_ALLOW_FILE_URLS"] = "1" if allow_file_urls
    Open3.capture3(
      environment,
      RbConfig.ruby,
      REVIEW_SCRIPT.to_s,
      "--review-manifest", @review_manifest_path.to_s,
      "--source-manifest", @source_manifest_path.to_s,
      "--source-inventory", @source_inventory_path.to_s,
      "--source-review-results",
      @corresponding_source_review_results_path.to_s,
      "--source-bundle", @source_bundle.to_s,
      *arguments,
      chdir: REPOSITORY_ROOT.to_s
    )
  end
end
