#!/usr/bin/env ruby

require "digest"
require "json"
require "optparse"
require "pathname"
require_relative "rootfs-corresponding-source-review-results"
require_relative "rootfs-source-acquisition"

module RootFSRebuildDeliveryEvidence
  class ValidationError < StandardError
  end

  ARCHIVE_VERSION = "v0.3.3"
  ARCHIVE_SHA256 =
    "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4"
  GENERATED_AT = "2026-07-27T00:00:00Z"

  HISTORICAL_BUILDER = {
    "repository" => "https://github.com/Lolendor/ish-arm64-pkg",
    "releaseTag" => "v0.3.3",
    "releaseTagObject" => "9ac7f73878d4b9109e96cb2c21a6537a89635ca4",
    "revision" => "6f96f02c71830914c2a608258a26a8ef0833d026",
    "tree" => "75a5fdedc64b2f80ada10eefe65c361d37a9408d",
    "buildScriptPath" => "scripts/build-rootfs.sh",
    "buildScriptSHA256" =>
      "5dc6883c9074e668a752e62f3d455e4742c1eb59bf3f43d3ebc023f3065b9387",
    "nestedIshRepository" => "https://github.com/Lolendor/ish-arm64",
    "nestedIshPath" => "third_party/ish",
    "nestedIshRevision" => "2f075626049d989dc9ac350a35c09f0b18930ffc"
  }.freeze

  SUCCESSOR_BUILDER = {
    "repository" => "https://github.com/jacklv-coder/ish-arm64-pkg",
    "revision" => "ae78b164b004c63419b628c4c68e4dc2d531a16c",
    "mergedByPullRequest" => 17,
    "mergeCommit" => "4755a001cdc248d0b3a1e120fbed5a4dace15a69",
    "sourceTree" => "499ed24fddc5adc9f874903303eca2043deee9ad",
    "buildScriptPath" => "scripts/build-rootfs.sh",
    "candidateScriptPath" => "scripts/prepare-rootfs-candidate.sh",
    "captureScriptPath" => "scripts/capture-rootfs-build-environment.py",
    "rootfsPinPath" => "scripts/alpine-rootfs-pin.sh",
    "nestedIshRepository" => "https://github.com/jacklv-coder/ish-arm64",
    "nestedIshPath" => "third_party/ish",
    "nestedIshRevision" => "c36dfd25462737b45559eb48d4b09f799471572e",
    "buildScriptSHA256" =>
      "89e9bee9c1033e9a4ca2128052ee6aa5cdaa98c857379e195bf4f914d734facd",
    "candidateScriptSHA256" =>
      "78911c4a144634da7125d3f2706ea54368cba3306e949fae550eae08e48b8520",
    "captureScriptSHA256" =>
      "7dd3d24e80d07ca0d5c5780ccb5c64da67a0f606c57398d9605e26ee529e01e0",
    "rootfsPinSHA256" =>
      "f30323374ae55272542819622c30ec447d5729b70061b5692d4bbf3338bba328"
  }.freeze

  SUCCESSOR_CANDIDATE = {
    "byteCount" => 6_513_474,
    "sha256" =>
      "445d41bbe9f8b1584ba8a4cac05300633e446763aa8a17e690c92b91dca03042",
    "identitySHA256" =>
      "b672da5f46ff2a1795c01f819d604f775a979c2f8432efb53588fcb70505f721",
    "receiptSHA256" =>
      "891c416bbfa7d34c672caadb5a527bf42448357ef2cb34de3117e66fdad24339",
    "checksumsSHA256" =>
      "20aca25a5f758234d4dcc7c4dbd70a434f6ae2cc8239e29def3a7706c090b512",
    "rootfsIdentitySchema" => 4,
    "rootfsRecipeSHA256" =>
      "b53f0d87ad50f779fad820502337c67ff4bb1e3c3f509dd27eb27bdd782b7d88",
    "stableHostToolProvenanceSHA256" =>
      "f64c6e89d8face8ba4de08dccd821d92eebf7d147add57cf1ebe6d536c956a3a",
    "alpineMinirootfs" => {
      "version" => "3.19.1",
      "architecture" => "aarch64",
      "url" =>
        "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/aarch64/" \
        "alpine-minirootfs-3.19.1-aarch64.tar.gz",
      "sha256" =>
        "7ef5eef3a5b1d198dfb1610cde1ef5b0755ff5d838fb1e5e1b9f42b59214820f"
    }
  }.freeze

  INVOCATIONS = [
    {
      "name" => "final-a",
      "candidateManifestSHA256" =>
        "29699c7e84eb9f0c2651c4ae9ad0ba95c7f86cebc24696b343c716d2a7acf476",
      "environmentReceiptSHA256" =>
        "e47fd77bd7add2ac00c1057ce6ff7fa8a2344b62ff50e78df42f1eeb120d0607",
      "hostFakefsifySHA256" =>
        "36e8bd718760ad0a99456e74131cd317a66dfcecba1cdee8602f49918395e2ad"
    },
    {
      "name" => "final-b",
      "candidateManifestSHA256" =>
        "2d95f7716e39cf40b7c142747400b895cdf1e7a5a6c444a9a6b6f00adc2e24d9",
      "environmentReceiptSHA256" =>
        "d7876497c8880ffa8fa5cfc44e313072cc3f750b5062bbf600770c64ea98c95e",
      "hostFakefsifySHA256" =>
        "fb78476f12170a5298cfc9948bd239bef697548c97960ee26e56dabcb78e25ba"
    }
  ].freeze

  TOOLCHAIN = {
    "host" => {
      "system" => "Darwin",
      "release" => "25.2.0",
      "machine" => "arm64",
      "platform" => "Darwin-25.2.0-arm64-arm-64bit-Mach-O"
    },
    "sanitizationPolicy" => "candidate-entrypoint-minimal-allowlist",
    "effectivePATH" => "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    "preservedVariableNames" => %w[
      TMPDIR HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY http_proxy
      https_proxy all_proxy no_proxy CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR
    ],
    "tools" => [
      {
        "name" => "bash",
        "resolvedPath" => "/bin/bash",
        "sha256" =>
          "07ad8525844ce61471e08e8c515b76bf063bac482394152bad814026cd577f69",
        "version" => "GNU bash 3.2.57(1)-release"
      },
      {
        "name" => "cc",
        "resolvedPath" => "/usr/bin/cc",
        "sha256" =>
          "3e7d30871a9740446f33a907b14d28f10ebe6d4e1c146a4c0788308f573a6609",
        "version" => "Apple clang 17.0.0 (clang-1700.4.4.1)"
      },
      {
        "name" => "curl",
        "resolvedPath" => "/usr/bin/curl",
        "sha256" =>
          "d9431c1ea04612844996bcbdf11d052afdc560116718f338ae6365ddb417e155",
        "version" => "curl 8.7.1"
      },
      {
        "name" => "git",
        "resolvedPath" => "/usr/bin/git",
        "sha256" =>
          "3e7d30871a9740446f33a907b14d28f10ebe6d4e1c146a4c0788308f573a6609",
        "version" => "git 2.50.1 (Apple Git-155)"
      },
      {
        "name" => "make",
        "resolvedPath" => "/usr/bin/make",
        "sha256" =>
          "3e7d30871a9740446f33a907b14d28f10ebe6d4e1c146a4c0788308f573a6609",
        "version" => "GNU Make 3.81"
      },
      {
        "name" => "meson",
        "resolvedPath" => "/opt/homebrew/Cellar/meson/1.11.2/bin/meson",
        "sha256" =>
          "0a0a2edc05d1a8ae7c84885f00dc5746ee1a57cc2c746e2b05a3b7dfbca2ed7d",
        "version" => "1.11.2"
      },
      {
        "name" => "ninja",
        "resolvedPath" => "/opt/homebrew/Cellar/ninja/1.13.2/bin/ninja",
        "sha256" =>
          "48761628046784f59bd789f5a72b88da99205c5849e5d19ae4d317854ae09e83",
        "version" => "1.13.2"
      },
      {
        "name" => "pkg-config",
        "resolvedPath" => "/opt/homebrew/Cellar/pkgconf/3.0.3/bin/pkgconf",
        "sha256" =>
          "d1c437b9ad16182ee781175ae4e69b439a91c6c6747a7cd50f878514212730e4",
        "version" => "3.0.3"
      },
      {
        "name" => "python3",
        "resolvedPath" =>
          "/opt/homebrew/Cellar/python@3.14/3.14.6/Frameworks/" \
          "Python.framework/Versions/3.14/bin/python3.14",
        "sha256" =>
          "4f00ea2ad53d62437a6a3946b73c73614a97e8accdc5b96dc095ea1a0d9c6a56",
        "version" => "Python 3.14.6"
      },
      {
        "name" => "shasum",
        "resolvedPath" => "/usr/bin/shasum",
        "sha256" =>
          "0812595f981a26f813d98dc380af14d4af427626c9339eda29eb849ae13de1e3",
        "version" => "6.02"
      },
      {
        "name" => "tar",
        "resolvedPath" => "/usr/bin/bsdtar",
        "sha256" =>
          "15e74e889ded97bd479391f47f6bb924ad2bef64f403995114f0841410d48039",
        "version" => "bsdtar 3.5.3 / libarchive 3.7.4"
      },
      {
        "name" => "zig",
        "resolvedPath" => "/opt/homebrew/Cellar/zig/0.16.0_1/bin/zig",
        "sha256" =>
          "0bfa8cb6f5f64c6d645e1d5dfb5c6f62c2b79d7249c3f38a279e118cb49b02ae",
        "version" => "0.16.0"
      },
      {
        "name" => "otool",
        "resolvedPath" => "/usr/bin/otool",
        "sha256" =>
          "3e7d30871a9740446f33a907b14d28f10ebe6d4e1c146a4c0788308f573a6609"
      }
    ],
    "linkedLibraries" => [
      {
        "loadPath" => "/opt/homebrew/opt/libarchive/lib/libarchive.13.dylib",
        "resolvedPath" =>
          "/opt/homebrew/Cellar/libarchive/3.8.8/lib/libarchive.13.dylib",
        "sha256" =>
          "636305de56ce2180fbdcccdcfd34bfc8a55b761a281cec987eb5563654edf8d1",
        "currentVersion" => "22.8.0",
        "storage" => "file"
      },
      {
        "loadPath" => "/usr/lib/libsqlite3.dylib",
        "currentVersion" => "377.0.0",
        "storage" => "dyld-shared-cache"
      },
      {
        "loadPath" => "/usr/lib/libSystem.B.dylib",
        "currentVersion" => "1356.0.0",
        "storage" => "dyld-shared-cache"
      }
    ],
    "environmentReceiptSchema" => 2,
    "ambientValuesCaptured" => false,
    "transportValuesCaptured" => false
  }.freeze

  module_function

  def pretty_json(document)
    "#{JSON.pretty_generate(document)}\n"
  end

  def sha256(contents)
    Digest::SHA256.hexdigest(contents)
  end

  def validate_inputs(
    source_acquisition,
    source_inventory,
    corresponding_source_review_results,
    source_acquisition_bytes:,
    source_inventory_bytes:,
    corresponding_source_review_results_bytes:
  )
    {
      "SOURCE-ACQUISITION.json" =>
        [source_acquisition, source_acquisition_bytes],
      "SOURCE-INVENTORY.json" => [source_inventory, source_inventory_bytes],
      "CORRESPONDING-SOURCE-REVIEW-RESULTS.json" => [
        corresponding_source_review_results,
        corresponding_source_review_results_bytes
      ]
    }.each do |name, (document, bytes)|
      unless JSON.parse(bytes) == document
        raise ValidationError, "#{name} bytes do not match the validated document"
      end
    rescue JSON::ParserError => error
      raise ValidationError, "#{name} bytes are invalid JSON: #{error.message}"
    end

    documents = {
      "SOURCE-ACQUISITION.json" => source_acquisition,
      "SOURCE-INVENTORY.json" => source_inventory,
      "CORRESPONDING-SOURCE-REVIEW-RESULTS.json" =>
        corresponding_source_review_results
    }
    documents.each do |name, document|
      archive = document["archive"]
      unless document["schemaVersion"] == 1 &&
        archive.is_a?(Hash) &&
        archive["version"] == ARCHIVE_VERSION &&
        archive["sha256"] == ARCHIVE_SHA256
        raise ValidationError, "#{name} does not bind the pinned RootFS archive"
      end
    end

    sources = source_acquisition["sources"]
    unless sources.is_a?(Array) &&
      sources.length == 10 &&
      sources.all? { |source| source["aportsSnapshot"].is_a?(Hash) }
      raise ValidationError, "Source acquisition does not contain ten typed source origins"
    end

    canonical_entry_count = sources.sum do |source|
      source.fetch("aportsSnapshot").fetch("regularFileCount")
    end
    distfile_count = sources.sum { |source| source.fetch("distfiles").length }
    review = corresponding_source_review_results
    begin
      RootFSSourceAcquisition.validate_manifest(
        source_acquisition,
        source_inventory
      )
      RootFSCorrespondingSourceReviewResults.validate_manifest(
        review,
        source_acquisition,
        source_inventory,
        source_acquisition_bytes: source_acquisition_bytes
      )
    rescue RootFSSourceAcquisition::ValidationError,
      RootFSCorrespondingSourceReviewResults::ValidationError => error
      raise ValidationError, "Invalid corresponding-source input: #{error.message}"
    end
    unless canonical_entry_count == 130 &&
      distfile_count == 9 &&
      review["reviewedSourceOriginCount"] == 10 &&
      review["reviewedCanonicalAportsEntryCount"] == canonical_entry_count &&
      review["reviewedDistfileCount"] == distfile_count &&
      review["sourceOriginsWithRemainingMaterialItems"] == 0 &&
      review["engineeringReviewCompleted"] == true &&
      review["completeCorrespondingSourceBundlePresent"] == false &&
      review["rebuildEnvironmentVerified"] == false &&
      review["correspondingSourceDeliveryApproved"] == false &&
      review["legalReviewApproved"] == false &&
      review["redistributionApproved"] == false
      raise ValidationError, "Corresponding-source engineering and release gates drifted"
    end
  end

  def build(
    source_acquisition:,
    source_inventory:,
    corresponding_source_review_results:,
    source_acquisition_bytes:,
    source_inventory_bytes:,
    corresponding_source_review_results_bytes:
  )
    validate_inputs(
      source_acquisition,
      source_inventory,
      corresponding_source_review_results,
      source_acquisition_bytes: source_acquisition_bytes,
      source_inventory_bytes: source_inventory_bytes,
      corresponding_source_review_results_bytes:
        corresponding_source_review_results_bytes
    )

    rebuild_review = {
      "schemaVersion" => 1,
      "generatedAt" => GENERATED_AT,
      "archive" => {
        "version" => ARCHIVE_VERSION,
        "sha256" => ARCHIVE_SHA256
      },
      "publishedArchiveBuild" => {
        "builderSource" => HISTORICAL_BUILDER,
        "sourceIdentified" => true,
        "exactBuildEnvironmentCaptured" => false,
        "exactPublishedArchiveRebuildVerified" => false,
        "limitations" => [
          "The historical builder accepted an empty ALPINE_SHA256 and " \
            "recorded the downloaded digest only after retrieval.",
          "The historical builder could select an ambient fakefsify " \
            "executable or locally built host tool without a pinned binary " \
            "or toolchain receipt.",
          "The historical archive path did not capture the normalized " \
            "environment and deterministic recipe evidence now required by " \
            "schema v4."
        ],
        "status" =>
          "historical-source-identified-exact-published-rebuild-unverified"
      },
      "successorCandidateBuild" => {
        "builderSource" => SUCCESSOR_BUILDER,
        "candidateArtifact" => SUCCESSOR_CANDIDATE,
        "toolchainEvidence" => TOOLCHAIN,
        "invocations" => INVOCATIONS,
        "independentInvocationCount" => 2,
        "buildsPerInvocation" => 2,
        "totalComparedBuildCount" => 4,
        "sameInvocationByteEqualityVerified" => true,
        "crossInvocationByteEqualityVerified" => true,
        "hostToolBytesEqualAcrossInvocations" => false,
        "hostToolSourceProvenanceEqualAcrossInvocations" => true,
        "crossHostReproducibilityVerified" => false,
        "crossOperatingSystemReproducibilityVerified" => false,
        "distributionAuthorized" => false,
        "status" =>
          "same-host-cross-invocation-reproducible-unapproved-successor"
      },
      "conclusions" => {
        "publishedArchiveExactRebuildEnvironmentVerified" => false,
        "publishedArchiveExactRebuildVerified" => false,
        "successorBuildEnvironmentCaptured" => true,
        "successorSameHostCrossInvocationReproducibilityVerified" => true,
        "successorCandidateMayReplacePinnedArchive" => false,
        "correspondingSourceDeliveryApproved" => false,
        "legalReviewApproved" => false,
        "redistributionApproved" => false
      },
      "status" =>
        "successor-reproducibility-verified-published-archive-gates-open"
    }
    rebuild_review_bytes = pretty_json(rebuild_review)

    delivery_inventory = {
      "schemaVersion" => 1,
      "generatedAt" => GENERATED_AT,
      "archive" => {
        "version" => ARCHIVE_VERSION,
        "sha256" => ARCHIVE_SHA256
      },
      "inputEvidence" => {
        "SOURCE-ACQUISITION.json" => {
          "sha256" => sha256(source_acquisition_bytes)
        },
        "SOURCE-INVENTORY.json" => {
          "sha256" => sha256(source_inventory_bytes)
        },
        "CORRESPONDING-SOURCE-REVIEW-RESULTS.json" => {
          "sha256" => sha256(corresponding_source_review_results_bytes)
        },
        "REBUILD-ENVIRONMENT-REVIEW.json" => {
          "sha256" => sha256(rebuild_review_bytes)
        }
      },
      "deliveryUnits" => [
        {
          "id" => "historical-rootfs-builder",
          "kind" => "git-source",
          "source" => HISTORICAL_BUILDER,
          "purpose" =>
            "identify the release-tagged builder source associated with the " \
            "pinned v0.3.3 archive",
          "indexed" => true,
          "materializedForDelivery" => false
        },
        {
          "id" => "successor-rootfs-builder",
          "kind" => "git-source",
          "source" => SUCCESSOR_BUILDER,
          "purpose" =>
            "provide the deterministic successor recipe and captured environment tooling",
          "indexed" => true,
          "materializedForDelivery" => false
        },
        {
          "id" => "alpine-minirootfs-input",
          "kind" => "pinned-binary-input",
          "source" => SUCCESSOR_CANDIDATE.fetch("alpineMinirootfs"),
          "purpose" => "bind the successor base userspace input",
          "indexed" => true,
          "materializedForDelivery" => false
        },
        {
          "id" => "installed-package-corresponding-source",
          "kind" => "aports-and-upstream-distfiles",
          "sourceOriginCount" => 10,
          "canonicalAportsEntryCount" => 130,
          "upstreamDistfileCount" => 9,
          "materializer" => "Scripts/prepare-rootfs-source-bundle.rb",
          "indexed" => true,
          "engineeringReviewed" => true,
          "materializedForDelivery" => false
        },
        {
          "id" => "rootfs-modifications",
          "kind" => "modification-disclosure",
          "items" => [
            "build and install the AArch64 /sbin/ishsv supervisor",
            "duplicate the Alpine userspace into /srv/vms/.template",
            "set base and template resolver, apk repositories, and hostnames",
            "convert the merged tar input into iSH fakefs metadata and data",
            "seal the initial fakefs identity and package it with " \
              "deterministic tar and gzip metadata"
          ],
          "indexed" => true,
          "materializedForDelivery" => false
        }
      ],
      "coverage" => {
        "deliveryUnitCount" => 5,
        "candidateSourceMaterialIndexComplete" => true,
        "modificationDisclosureIndexed" => true,
        "successorRebuildEvidenceIndexed" => true,
        "materializedCorrespondingSourceBundlePresent" => false,
        "completeLicenseAndNoticeBundlePresent" => false,
        "sourceOfferPrepared" => false,
        "deliveryMechanismApproved" => false,
        "legalReviewApproved" => false,
        "redistributionApproved" => false
      },
      "status" =>
        "complete-engineering-inventory-materialization-and-approval-open"
    }

    {
      "REBUILD-ENVIRONMENT-REVIEW.json" => rebuild_review_bytes,
      "SOURCE-DELIVERY-INVENTORY.json" => pretty_json(delivery_inventory)
    }
  end

  def load_json(path, label)
    bytes = path.binread
    [JSON.parse(bytes), bytes]
  rescue JSON::ParserError => error
    raise ValidationError, "#{label} is invalid JSON: #{error.message}"
  end

  def check(directory)
    source_acquisition, source_acquisition_bytes =
      load_json(directory.join("SOURCE-ACQUISITION.json"), "Source acquisition")
    source_inventory, source_inventory_bytes =
      load_json(directory.join("SOURCE-INVENTORY.json"), "Source inventory")
    review, review_bytes = load_json(
      directory.join("CORRESPONDING-SOURCE-REVIEW-RESULTS.json"),
      "Corresponding-source review results"
    )
    expected = build(
      source_acquisition: source_acquisition,
      source_inventory: source_inventory,
      corresponding_source_review_results: review,
      source_acquisition_bytes: source_acquisition_bytes,
      source_inventory_bytes: source_inventory_bytes,
      corresponding_source_review_results_bytes: review_bytes
    )
    failures = expected.each_with_object([]) do |(filename, contents), result|
      path = directory.join(filename)
      if !path.file?
        result << "missing #{path}"
      elsif path.binread != contents
        result << "out of date #{path}"
      end
    end
    unless failures.empty?
      raise ValidationError,
        "RootFS rebuild/delivery evidence is not reproducible:\n- " \
        "#{failures.join("\n- ")}"
    end
    expected
  end
end

if __FILE__ == $PROGRAM_NAME
  options = {
    directory: Pathname("Compliance/RootFS/v0.3.3")
  }
  parser = OptionParser.new do |commands|
    commands.banner = "Usage: ruby Scripts/rootfs-rebuild-delivery-evidence.rb [options]"
    commands.on("--directory DIR", "RootFS compliance evidence directory") do |path|
      options[:directory] = Pathname(path)
    end
  end

  begin
    parser.parse!
    raise OptionParser::InvalidOption, ARGV.join(" ") unless ARGV.empty?
    outputs = RootFSRebuildDeliveryEvidence.check(options.fetch(:directory))
    puts "RootFS rebuild/delivery evidence is reproducible " \
      "(#{outputs.length} files)."
  rescue RootFSRebuildDeliveryEvidence::ValidationError,
    OptionParser::ParseError, SystemCallError => error
    warn error.message
    exit 1
  end
end
