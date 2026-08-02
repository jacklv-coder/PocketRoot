#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "securerandom"
require "time"
require "yaml"
require_relative "pocketroot-deterministic-json"
require_relative "scan-release-artifact"

module PocketRootReleaseCompliance
  RELEASE_VERSION = "0.1.0"
  GENERATED_AT = "2026-07-28T00:00:00Z"
  OUTPUT_RELATIVE = "Compliance/Release/experimental-v0.1.0"
  MIT_LICENSE_TEXT = <<~LICENSE.freeze
    MIT License

    Copyright (c) 2026 PocketRoot contributors

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
  LICENSE
  ISHEMBED = {
    "repository" => "https://github.com/jacklv-coder/ish-arm64-pkg.git",
    "revision" => "2419f736b271beb52a699b2f780027cf280472b8",
    "packageVersion" => "0.4.0-abi.9.1",
    "release" => "0.4.0-abi.9.1",
    "assetRelease" => "v0.4.0-abi.9",
    "licenseDeclared" => "GPL-3.0-or-later",
    "xcframework" => {
      "filename" => "libIshKernel.xcframework.zip",
      "url" =>
        "https://github.com/jacklv-coder/ish-arm64-pkg/releases/download/" \
        "v0.4.0-abi.9/libIshKernel.xcframework.zip",
      "byteCount" => 2_460_178,
      "sha256" =>
        "c68f47587686000cf125105ac25eaf4d79de6dbd1715d39838bfb7d35abc72f8"
    },
    "correspondingSource" => {
      "filename" => "IshEmbed-corresponding-source.tar.gz",
      "url" =>
        "https://github.com/jacklv-coder/ish-arm64-pkg/releases/download/" \
        "v0.4.0-abi.9/IshEmbed-corresponding-source.tar.gz",
      "byteCount" => 2_391_682,
      "sha256" =>
        "8e5d3d56056ece402c09e5f1b3cbdaad75f2f8697ed0e41eaeecd7c403f26557"
    },
    "ish" => {
      "repository" => "https://github.com/jacklv-coder/ish-arm64.git",
      "path" => "third_party/ish",
      "revision" => "3d0b4f6f55108f6d602ac6a2c86df555935b979d",
      "licenseDeclared" => "GPL-3.0-only OR GPL-2.0-only"
    },
    "supervisor" => {
      "toolchain" => "Zig 0.16.0",
      "target" => "aarch64-linux-musl",
      "zigSha256" =>
        "0bfa8cb6f5f64c6d645e1d5dfb5c6f62c2b79d7249c3f38a279e118cb49b02ae",
      "muslSourceSha256" =>
        "fd6449aeff0aaec6bd9688618ab973cf68cbc36c60eacea6598ee407eda8a35b",
      "muslLicenseDeclared" => "MIT"
    }
  }.freeze
  SWIFTTERM = {
    "repository" => "https://github.com/jacklv-coder/SwiftTerm.git",
    "revision" => "dd2fb8ac5b861e7bf617c872895e338f38165648",
    "packageVersion" => "1.15.0-pocketroot.1",
    "release" => "1.15.0-pocketroot.1",
    "licenseDeclared" => "MIT",
    "noticePath" => "ThirdPartyNotices/SwiftTerm-LICENSE.txt",
    "noticeSha256" =>
      "1c34c11581e20feb2b7ea122146a6690261dae94b2c8444e8cff902e567df6ae"
  }.freeze
  SWIFT_ARGUMENT_PARSER = {
    "repository" => "https://github.com/apple/swift-argument-parser",
    "revision" => "6a52f3251125d74daf04fcbd5e6f08a75d074382",
    "release" => "1.8.2",
    "licenseDeclared" => "Apache-2.0",
    "resolvedOnly" => true
  }.freeze
  SPDX_LICENSE_LIST = {
    "path" => "Compliance/SPDX/LICENSE-LIST-3.28.0.json",
    "version" => "3.28.0",
    "releaseDate" => "2026-02-20T00:00:00Z",
    "repository" => "https://github.com/spdx/license-list-data.git",
    "revision" => "c4a7237ec8f4654e867546f9f409749300f1bf4c",
    "licensesJsonSha256" =>
      "f728c534d8bd1044fc515a2ddb2292be99559021d830bfa3281be0bcd36302ee",
    "exceptionsJsonSha256" =>
      "bd145bb558f44432fcd6f0d7e956ed0124dff72af7641a7cfcb1b557dc390a5b",
    "licenseCount" => 695,
    "exceptionCount" => 83
  }.freeze
  FINAL_ARTIFACT_EVIDENCE_RELATIVE =
    "Compliance/Release/FinalArtifact/v0.1.0"
  FINAL_ARTIFACT_INVENTORY_RELATIVE =
    "#{FINAL_ARTIFACT_EVIDENCE_RELATIVE}/ARTIFACT-INVENTORY.json"
  FINAL_ARTIFACT_SBOM_RELATIVE =
    "#{FINAL_ARTIFACT_EVIDENCE_RELATIVE}/SBOM.spdx.json"
  ROOTFS = {
    "version" => "v0.3.3",
    "guestVersion" => "3.19.1",
    "architecture" => "aarch64",
    "filename" => "fs.tar.gz",
    "url" =>
      "https://github.com/Lolendor/ish-arm64-pkg/releases/download/v0.3.3/" \
      "fs.tar.gz",
    "byteCount" => 6_581_376,
    "sha256" =>
      "be0f3c133f78f28b023288459b33dc28fa253a6ef29f7123bc5f3892edf90ad4",
    "evidenceSha256" =>
      "98170847e01c3c738d600970ca479202e7f69bf9f3b2cef31138462d0bfc3deb",
    "sbomSha256" =>
      "8e021cb8c4160c934a0202609691d7a94526cd016f4394a47da6e7a5ab41d0ea"
  }.freeze
  EXPECTED_PRODUCTS = {
    "PocketRootCore" => ["PocketRootCore"],
    "PocketRootTerminal" => ["PocketRootTerminal"],
    "PocketRootResources" => ["PocketRootResources"],
    "PocketRootIshRuntime" => ["PocketRootIshRuntime"],
    "PocketRootIshRuntimeIntegration" =>
      ["PocketRootIshRuntimeIntegration"],
    "PocketRootAgent" => ["PocketRootAgent"],
    "PocketRootAgentRuntimeTools" => ["PocketRootAgentRuntimeTools"],
    "PocketRoot" => ["PocketRoot"]
  }.freeze
  EXPECTED_SWIFT_TARGETS = {
    "PocketRootCore" => {
      "dependencies" => [],
      "resources" => []
    },
    "PocketRootTerminal" => {
      "dependencies" => [
        "target:PocketRootCore",
        "product:SwiftTerm@SwiftTerm[iOS]"
      ],
      "resources" => []
    },
    "CPocketRootArchiveSupport" => {
      "dependencies" => [],
      "resources" => []
    },
    "PocketRootResources" => {
      "dependencies" => ["target:CPocketRootArchiveSupport"],
      "resources" => ["process:Resources"]
    },
    "PocketRootIshRuntime" => {
      "dependencies" => [
        "target:PocketRootCore",
        "product:IshEmbed@ish-arm64-pkg[iOS]"
      ],
      "resources" => []
    },
    "PocketRootIshRuntimeIntegration" => {
      "dependencies" => [
        "target:PocketRootCore",
        "target:PocketRootResources",
        "target:PocketRootIshRuntime",
        "target:PocketRootTerminal"
      ],
      "resources" => []
    },
    "PocketRootAgent" => {
      "dependencies" => [],
      "resources" => []
    },
    "PocketRootAgentRuntimeTools" => {
      "dependencies" => [
        "target:PocketRootAgent",
        "target:PocketRootCore"
      ],
      "resources" => []
    },
    "PocketRoot" => {
      "dependencies" => [
        "target:PocketRootCore",
        "target:PocketRootTerminal",
        "target:PocketRootResources"
      ],
      "resources" => []
    }
  }.freeze
  EXPECTED_SWIFT_TEST_TARGETS = {
    "PocketRootCoreTests" => {
      "dependencies" => ["target:PocketRootCore"],
      "resources" => []
    },
    "PocketRootTerminalTests" => {
      "dependencies" => ["target:PocketRootTerminal"],
      "resources" => []
    },
    "PocketRootResourcesTests" => {
      "dependencies" => ["target:PocketRootResources"],
      "resources" => []
    },
    "PocketRootIshRuntimeTests" => {
      "dependencies" => [
        "target:PocketRootCore",
        "target:PocketRootIshRuntime"
      ],
      "resources" => []
    },
    "PocketRootIshRuntimeIntegrationTests" => {
      "dependencies" => [
        "target:PocketRootCore",
        "target:PocketRootResources",
        "target:PocketRootIshRuntimeIntegration"
      ],
      "resources" => []
    },
    "PocketRootAgentTests" => {
      "dependencies" => ["target:PocketRootAgent"],
      "resources" => []
    },
    "PocketRootAgentRuntimeToolsTests" => {
      "dependencies" => [
        "target:PocketRootAgent",
        "target:PocketRootAgentRuntimeTools",
        "target:PocketRootCore"
      ],
      "resources" => []
    }
  }.freeze
  EXPECTED_RESOURCE_FILES = {
    "Examples/PocketRootDemo/Sources/PocketRootDemo/Resources/Assets.xcassets/Contents.json" =>
      "0fd49ba3c3585c709678e0046a821c3c60685ec7063720d30d3a3448be3a208b",
    "Sources/PocketRootResources/Resources/.gitkeep" =>
      "01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b",
    "Sources/PocketRootResources/Resources/README.txt" =>
      "41df51e7edc0774f807c1cb7e423e2cd04f2a1029ac2d6bbcd097f9bb679a5ea"
  }.freeze
  EXPECTED_REPOSITORY_FILES = {
    "LICENSE" =>
      "2716cea9e81c7dce0a87260c7643d46cf99b34d156186c1a1dbda388aafdd143",
    "NOTICE.md" =>
      "572b60c39125dae2f7e7c2ae83c6c5b79dc2fedd863bf658f3c0e100825cdd2e",
    "CONTRIBUTING.md" =>
      "0beaceb8d56f1c43fa458d0b121d3d005c4a9cedb12b32029b35e74aff7b3d0b",
    "CONTRIBUTING.en.md" =>
      "0f619a667ea5ae4749f77f9afe5a9583447fcdab8a0985c11dcc4c935dead94a",
    "Compliance/SPDX/LICENSE-LIST-3.28.0.json" =>
      "7376db20698ff21511fe802aded9b5d7145520a86133b74f68b0c1568dd6dd1c",
    "Compliance/Release/RELEASE-DECISIONS.json" =>
      "5dfed061b0def6cca5572becece0b4de1fc34af53c501c9c0e7b647f02e4cf7f",
    "Package.resolved" =>
      "a121fd0f287bcb42e22d1860f915203447dd552fddc82461e9d385b957fb3718",
    "Package.swift" =>
      "9ec4f31f7a91c5c001b6e5826c5ab2824e98c06eb61444027485a70f1efccfff",
    "Examples/PocketRootDemo/project.yml" =>
      "749cfea0c9a9e7cc4919d3dbee1c01720aa85d8f1b5fe4fc887b61d3a2d0f3fa",
    "Examples/PocketRootHostApp/project.yml" =>
      "5d2961cd344b85b5ca0102f3e7b80c3bba7ac8681b645e3d8efae0ec137d33e4",
    "Examples/PocketRootQuickStartApp/project.yml" =>
      "11c6f86f3be0f419a9a6f10dc884b4df9cb157bcdccb5568fe903972a6084416",
    "Tests/Integration/ExternalConsumerApp/project.yml.template" =>
      "95ca1929e779b1b91a304e68261c94ce42839b833a4e55a9768daa05b437cfb9",
    "Scripts/inject-demo-rootfs.sh" =>
      "3982b5382b0d1e13e0c8e8a5bb5404c5bad1dfc4d6e9cd23a39e3395a83087bb",
    "Scripts/scan-release-artifact.rb" =>
      "48f27ab280491864228393e1675fe3a2889cbd616f79e3cb16bae7efedf647c0",
    "Scripts/run-host-app-device-ui-smoke.sh" =>
      "2f934265cb46145b27bb26e0d7e84acebc14290602e23cd1ab8f222aef68ed1f",
    "Scripts/run-host-app-ui-smoke.sh" =>
      "c8b11b1bf3a467fd10ed2c4124a72396b0a803e98f155d1d709fab46b59eede1",
    "Scripts/run-ios-example-ui-smoke.sh" =>
      "071fa3336479f1849eb3be3f1f6b6516025197a0cf30640e64cd902282d9ed4d",
    "Scripts/run-quick-start-ui-smoke.sh" =>
      "acf26d68fc37250e24911c2d23791a0d12ff06a624dedcefee0ed7905bc31af2",
    "Scripts/run-external-consumer-ui-smoke.sh" =>
      "d9544ede3ecbad8d42a114015fa77071d31aa84aafc1cbe0f0f001453b1a4d0d",
    "ThirdPartyNotices/SwiftTerm-LICENSE.txt" =>
      "1c34c11581e20feb2b7ea122146a6690261dae94b2c8444e8cff902e567df6ae"
  }.freeze
  IMPLEMENTATION_ROOTS = %w[
    Sources
    Examples/PocketRootDemo/Sources/PocketRootDemo
    Examples/PocketRootHostApp/Sources
    Examples/PocketRootHostApp/UITests
    Examples/PocketRootQuickStartApp/Sources
    Examples/PocketRootQuickStartApp/UITests
    Tests/Integration/ExternalConsumerApp/Sources
    Tests/Integration/ExternalConsumerApp/UITests
    Spikes/PocketRootIshRuntimeCompileSpike
    Spikes/PocketRootIshRuntimeSmoke
  ].freeze
  EXPECTED_PROJECT_TARGETS = %w[
    PocketRootIshRuntimeCompileSpike
    PocketRootIshRuntimeSmoke
    PocketRootDemo
    PocketRootDemoTests
  ].freeze
  OUTPUT_FILENAMES = %w[
    COMPOSITION.json
    READINESS.json
    README.md
    RELEASE-CHECKLIST.md
    SBOM.spdx.json
    SHA256SUMS
  ].freeze
  # These spellings match the pinned official SPDX 2.3 JSON schema exactly;
  # its operating-system enum deliberately uses an underscore.
  SPDX_PACKAGE_PURPOSES = %w[
    APPLICATION
    FRAMEWORK
    LIBRARY
    CONTAINER
    OPERATING_SYSTEM
    DEVICE
    FIRMWARE
    SOURCE
    ARCHIVE
    FILE
    INSTALL
    OTHER
  ].freeze
  HASH_PATTERN = /\A[0-9a-f]{64}\z/

  class ComplianceError < StandardError
  end

  module_function

  def repository_root
    override = ENV["POCKETROOT_RELEASE_REPOSITORY_ROOT"]
    return Pathname(__dir__).parent.realpath unless override

    root = Pathname(override)
    unless root.absolute? && root.directory? && !root.symlink?
      raise ComplianceError,
        "POCKETROOT_RELEASE_REPOSITORY_ROOT must be a real absolute directory"
    end
    root.realpath
  end

  def output_directory
    repository_root.join(OUTPUT_RELATIVE)
  end

  def pretty_json(value)
    PocketRootDeterministicJSON.dump(
      value,
      error_class: ComplianceError
    )
  end

  def read_regular(path, label, maximum_bytes: 16 * 1_024 * 1_024)
    pathname = Pathname(path)
    if pathname.symlink? || !pathname.exist? || !pathname.lstat.file?
      raise ComplianceError, "#{label} is not a real regular file: #{pathname}"
    end
    if pathname.size > maximum_bytes
      raise ComplianceError, "#{label} exceeds #{maximum_bytes} bytes"
    end
    pathname.binread
  end

  def load_json(path, label)
    contents = read_regular(path, label)
    [JSON.parse(contents), contents]
  rescue JSON::ParserError => error
    raise ComplianceError, "#{label} is invalid JSON: #{error.message}"
  end

  def implementation_file_sha256(root)
    files = {}
    IMPLEMENTATION_ROOTS.each do |relative_root|
      directory = root.join(relative_root)
      if directory.symlink? || !directory.directory?
        raise ComplianceError,
          "release-composition implementation root is invalid: #{relative_root}"
      end
      Dir.glob(
        directory.join("**", "*").to_s,
        File::FNM_DOTMATCH
      ).sort.each do |entry|
        path = Pathname(entry)
        next if %w[. ..].include?(path.basename.to_s)
        if path.symlink?
          raise ComplianceError,
            "release-composition implementation path is a symlink: #{path}"
        end
        next if path.directory?
        unless path.file?
          raise ComplianceError,
            "release-composition implementation path is not a file: #{path}"
        end
        relative = path.relative_path_from(root).to_s
        contents =
          read_regular(path, "release-composition implementation #{relative}")
        files[relative] = Digest::SHA256.hexdigest(contents)
      end
    end
    if files.empty?
      raise ComplianceError, "release-composition implementation tree is empty"
    end
    files
  end

  def delimited_body(source, start_index, opening, closing, label)
    opening_index = source.index(opening, start_index)
    raise ComplianceError, "#{label} is missing #{opening}" unless opening_index
    depth = 0
    in_string = false
    escaped = false
    source.each_char.with_index do |character, index|
      next if index < opening_index
      if in_string
        if escaped
          escaped = false
        elsif character == "\\"
          escaped = true
        elsif character == '"'
          in_string = false
        end
        next
      end
      if character == '"'
        in_string = true
      elsif character == opening
        depth += 1
      elsif character == closing
        depth -= 1
        return source[(opening_index + 1)...index] if depth.zero?
      end
    end
    raise ComplianceError, "#{label} has an unterminated #{opening}"
  end

  def swift_call_bodies(source, token, label)
    bodies = []
    offset = 0
    while (token_index = source.index(token, offset))
      opening_index = source.index("(", token_index + token.length)
      unless opening_index
        raise ComplianceError, "#{label} has a malformed #{token} call"
      end
      body =
        delimited_body(source, opening_index, "(", ")", "#{label} #{token}")
      bodies << body
      offset = opening_index + body.length + 2
    end
    bodies
  end

  def swift_array(source, key, label)
    key_match = source.match(/\b#{Regexp.escape(key)}\s*:/)
    return nil unless key_match
    delimited_body(source, key_match.end(0), "[", "]", "#{label} #{key}")
  end

  def swift_manifest_array(source, key)
    matches = source.enum_for(
      :scan,
      /^    #{Regexp.escape(key)}\s*:/
    ).map { Regexp.last_match }
    unless matches.length == 1
      raise ComplianceError,
        "Package.swift must contain one top-level #{key} array"
    end
    delimited_body(
      source,
      matches.fetch(0).end(0),
      "[",
      "]",
      "Package.swift #{key}"
    )
  end

  def parse_swift_target(body)
    name = body[/\bname:\s*"([^"]+)"/, 1]
    raise ComplianceError, "Package.swift target is missing a name" unless name
    dependency_source =
      swift_array(body, "dependencies", "Package.swift target #{name}")
    dependencies =
      if dependency_source
        target_matches =
          dependency_source.scan(/^\s*"([^"]+)"\s*,?\s*$/)
        targets = target_matches.flatten.map do |value|
            "target:#{value}"
          end
        product_bodies =
          swift_call_bodies(
            dependency_source,
            ".product",
            "Package.swift target #{name} dependencies"
          )
        products = product_bodies.map do |product|
            product_name = product[/\bname:\s*"([^"]+)"/, 1]
            package_name = product[/\bpackage:\s*"([^"]+)"/, 1]
            condition =
              if product.match?(
                /\bcondition:\s*\.when\(\s*platforms:\s*\[\.iOS\]\s*\)/
              )
                "[iOS]"
              else
                ""
              end
            unless product_name && package_name
              raise ComplianceError,
                "Package.swift target #{name} has an invalid product dependency"
            end
            "product:#{product_name}@#{package_name}#{condition}"
          end
        unparsed = dependency_source.dup
        unparsed.gsub!(/^\s*"[^"]+"\s*,?\s*$/, "")
        product_bodies.each do |product|
          unless unparsed.sub!(".product(#{product})", "")
            raise ComplianceError,
              "Package.swift target #{name} has an unparsed product dependency"
          end
        end
        unless unparsed.gsub(/[,\s]/, "").empty?
          raise ComplianceError,
            "Package.swift target #{name} has an unsupported dependency"
        end
        targets + products
      else
        []
      end
    resource_source =
      swift_array(body, "resources", "Package.swift target #{name}")
    resources =
      if resource_source
        matches = resource_source.scan(
          /\.(process|copy)\(\s*"([^"]+)"\s*\)/
        )
        unparsed = resource_source.dup
        unparsed.gsub!(/\.(?:process|copy)\(\s*"[^"]+"\s*\)/, "")
        unless unparsed.gsub(/[,\s]/, "").empty?
          raise ComplianceError,
            "Package.swift target #{name} has an unsupported resource rule"
        end
        matches.map { |kind, path| "#{kind}:#{path}" }
      else
        []
      end
    {
      "name" => name,
      "dependencies" => dependencies,
      "resources" => resources
    }
  end

  def parse_package_manifest(contents)
    unless contents.start_with?("// swift-tools-version: 5.10\n") &&
      contents.match?(/\bname:\s*"PocketRoot"/) &&
      contents.match?(/\.iOS\("18\.0"\)/)
      raise ComplianceError,
        "Package.swift does not preserve the package identity and platform floor"
    end

    product_source = swift_manifest_array(contents, "products")
    product_bodies =
      swift_call_bodies(product_source, ".library", "Package.swift products")
    products = {}
    product_bodies.each do |body|
      match = body.match(
        /\A\s*name:\s*"([^"]+)"\s*,\s*targets:\s*\[([^\]]+)\]\s*\z/m
      )
      unless match
        raise ComplianceError, "Package.swift has an invalid library product"
      end
      name = match[1]
      target_source = match[2]
      targets = target_source.scan(/"([^"]+)"/).flatten
      if products.key?(name) || targets.empty?
        raise ComplianceError, "Package.swift has an invalid product declaration"
      end
      products[name] = targets
    end
    unparsed_products = product_source.dup
    product_bodies.each do |body|
      unless unparsed_products.sub!(".library(#{body})", "")
        raise ComplianceError, "Package.swift has an unparsed library product"
      end
    end
    unless unparsed_products.gsub(/[,\s]/, "").empty?
      raise ComplianceError, "Package.swift has an unsupported product declaration"
    end
    unless products == EXPECTED_PRODUCTS
      raise ComplianceError, "Package.swift product graph drifted"
    end
    target_source = swift_manifest_array(contents, "targets")
    targets =
      swift_call_bodies(target_source, ".target", "Package.swift targets").map do |body|
        parse_swift_target(body)
      end
    target_graph = targets.to_h do |target|
      [
        target.fetch("name"),
        {
          "dependencies" => target.fetch("dependencies"),
          "resources" => target.fetch("resources")
        }
      ]
    end
    unless targets.length == target_graph.length &&
      target_graph == EXPECTED_SWIFT_TARGETS
      raise ComplianceError, "Package.swift target graph drifted"
    end
    test_targets =
      swift_call_bodies(
        target_source,
        ".testTarget",
        "Package.swift targets"
      ).map do |body|
        parse_swift_target(body)
      end
    test_target_graph = test_targets.to_h do |target|
      [
        target.fetch("name"),
        {
          "dependencies" => target.fetch("dependencies"),
          "resources" => target.fetch("resources")
        }
      ]
    end
    unless test_targets.length == test_target_graph.length &&
      test_target_graph == EXPECTED_SWIFT_TEST_TARGETS
      raise ComplianceError, "Package.swift test target graph drifted"
    end
    unparsed_targets = target_source.dup
    [
      [".target", targets],
      [".testTarget", test_targets]
    ].each do |token, parsed_targets|
      bodies = swift_call_bodies(target_source, token, "Package.swift targets")
      unless bodies.length == parsed_targets.length
        raise ComplianceError, "Package.swift target parser lost declarations"
      end
      bodies.each do |body|
        unless unparsed_targets.sub!("#{token}(#{body})", "")
          raise ComplianceError, "Package.swift has an unparsed target declaration"
        end
      end
    end
    unless unparsed_targets.gsub(/[,\s]/, "").empty?
      raise ComplianceError, "Package.swift has an unsupported target declaration"
    end

    dependency_source = swift_manifest_array(contents, "dependencies")
    dependency_bodies =
      swift_call_bodies(
        dependency_source,
        ".package",
        "Package.swift dependencies"
      )
    expected_direct_dependencies = [ISHEMBED, SWIFTTERM]
    expected_dependency =
      dependency_bodies.length == expected_direct_dependencies.length &&
      dependency_bodies.zip(expected_direct_dependencies).all? do |body, expected|
        body.match?(
          /\A\s*url:\s*"#{Regexp.escape(expected.fetch("repository"))}"\s*,\s*/m
        ) &&
          body.match?(
            /exact:\s*"#{Regexp.escape(expected.fetch("packageVersion"))}"\s*\z/m
          )
      end
    unparsed_dependencies = dependency_source.dup
    dependency_bodies.each do |body|
      unparsed_dependencies.sub!(".package(#{body})", "")
    end
    unless expected_dependency &&
      unparsed_dependencies.gsub(/[,\s]/, "").empty?
      raise ComplianceError,
        "Package.swift external dependency declarations do not match the pins"
    end
    {
      "name" => "PocketRoot",
      "toolsVersion" => "5.10",
      "minimumIOSVersion" => "18.0",
      "products" => products.map do |name, targets|
        {"name" => name, "targets" => targets}
      end,
      "targets" => targets,
      "testTargets" => test_targets
    }
  end

  def parse_package_resolved(document)
    unless document.is_a?(Hash) &&
      document.keys.sort == %w[originHash pins version].sort &&
      document["version"] == 3 &&
      document["originHash"].is_a?(String) &&
      document["originHash"].match?(HASH_PATTERN)
      raise ComplianceError, "Package.resolved has an unsupported schema"
    end
    pins = document.fetch("pins")
    expected_pins = [
      {
        "identity" => "ish-arm64-pkg",
        "kind" => "remoteSourceControl",
        "location" => ISHEMBED.fetch("repository"),
        "state" => {
          "revision" => ISHEMBED.fetch("revision"),
          "version" => ISHEMBED.fetch("packageVersion")
        }
      },
      {
        "identity" => "swift-argument-parser",
        "kind" => "remoteSourceControl",
        "location" => SWIFT_ARGUMENT_PARSER.fetch("repository"),
        "state" => {
          "revision" => SWIFT_ARGUMENT_PARSER.fetch("revision"),
          "version" => SWIFT_ARGUMENT_PARSER.fetch("release")
        }
      },
      {
        "identity" => "swiftterm",
        "kind" => "remoteSourceControl",
        "location" => SWIFTTERM.fetch("repository"),
        "state" => {
          "revision" => SWIFTTERM.fetch("revision"),
          "version" => SWIFTTERM.fetch("packageVersion")
        }
      }
    ]
    unless pins == expected_pins
      raise ComplianceError, "Package.resolved external pins drifted"
    end
    pins
  rescue KeyError, TypeError => error
    raise ComplianceError, "Package.resolved is incomplete: #{error.message}"
  end

  def parse_project(contents)
    project =
      YAML.safe_load(
        contents,
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
    expected_options = {
      "bundleIdPrefix" => "com.jacklv",
      "deploymentTarget" => {"iOS" => "18.0"},
      "createIntermediateGroups" => true,
      "generateEmptyDirectories" => true
    }
    expected_settings = {
      "base" => {
        "SWIFT_VERSION" => "5.0",
        "IPHONEOS_DEPLOYMENT_TARGET" => "18.0",
        "TARGETED_DEVICE_FAMILY" => "1,2",
        "GENERATE_INFOPLIST_FILE" => true,
        "CURRENT_PROJECT_VERSION" => 1,
        "MARKETING_VERSION" => RELEASE_VERSION,
        "SWIFT_STRICT_CONCURRENCY" => "targeted"
      }
    }
    unless project.is_a?(Hash) &&
      project["name"] == "PocketRootDemo" &&
      project["options"] == expected_options &&
      project["settings"] == expected_settings &&
      project["packages"] == {"PocketRoot" => {"path" => "../.."}}
      raise ComplianceError,
        "project.yml does not preserve exact project settings and package inputs"
    end
    targets = project.fetch("targets")
    unless targets.is_a?(Hash) &&
      targets.keys == EXPECTED_PROJECT_TARGETS
      raise ComplianceError, "project.yml target set drifted"
    end
    expected_composition = {
      "PocketRootIshRuntimeCompileSpike" => {
        "type" => "application",
        "platform" => "iOS",
        "deploymentTarget" => "18.0",
        "settings" => {
          "base" => {
            "PRODUCT_BUNDLE_IDENTIFIER" =>
              "com.jacklv.PocketRootIshRuntimeCompileSpike",
            "PRODUCT_NAME" => "PocketRootIshRuntimeCompileSpike",
            "ARCHS" => "arm64",
            "EXCLUDED_ARCHS[sdk=iphonesimulator*]" => "x86_64",
            "ONLY_ACTIVE_ARCH" => true,
            "SKIP_INSTALL" => true,
            "SUPPORTS_MACCATALYST" => false,
            "ENABLE_DEBUG_DYLIB" => false,
            "INFOPLIST_KEY_UILaunchScreen_Generation" => true
          }
        },
        "sources" => [
          {"path" => "../../Spikes/PocketRootIshRuntimeCompileSpike"}
        ],
        "resources" => [],
        "dependencies" => [
          {
            "package" => "PocketRoot",
            "product" => "PocketRootIshRuntimeIntegration"
          }
        ],
        "postBuildScripts" => []
      },
      "PocketRootIshRuntimeSmoke" => {
        "type" => "application",
        "platform" => "iOS",
        "deploymentTarget" => "18.0",
        "settings" => {
          "base" => {
            "PRODUCT_BUNDLE_IDENTIFIER" =>
              "com.jacklv.PocketRootIshRuntimeSmoke",
            "PRODUCT_NAME" => "PocketRootIshRuntimeSmoke",
            "ARCHS" => "arm64",
            "EXCLUDED_ARCHS[sdk=iphonesimulator*]" => "x86_64",
            "ONLY_ACTIVE_ARCH" => true,
            "SKIP_INSTALL" => false,
            "SUPPORTS_MACCATALYST" => false,
            "ENABLE_DEBUG_DYLIB" => false,
            "INFOPLIST_KEY_UILaunchScreen_Generation" => true
          }
        },
        "sources" => [
          {"path" => "../../Spikes/PocketRootIshRuntimeSmoke"}
        ],
        "resources" => [],
        "dependencies" => [
          {"package" => "PocketRoot", "product" => "PocketRootCore"},
          {
            "package" => "PocketRoot",
            "product" => "PocketRootIshRuntimeIntegration"
          },
          {"package" => "PocketRoot", "product" => "PocketRootResources"},
          {"package" => "PocketRoot", "product" => "PocketRootTerminal"}
        ],
        "postBuildScripts" => []
      },
      "PocketRootDemo" => {
        "type" => "application",
        "platform" => "iOS",
        "deploymentTarget" => "18.0",
        "settings" => {
          "base" => {
            "PRODUCT_BUNDLE_IDENTIFIER" => "com.jacklv.PocketRootDemo",
            "PRODUCT_NAME" => "PocketRootDemo",
            "ARCHS" => "arm64",
            "EXCLUDED_ARCHS[sdk=iphonesimulator*]" => "x86_64",
            "ONLY_ACTIVE_ARCH" => true,
            "SUPPORTS_MACCATALYST" => false,
            "ENABLE_DEBUG_DYLIB" => false,
            "ENABLE_USER_SCRIPT_SANDBOXING" => false,
            "SWIFT_STRICT_CONCURRENCY" => "complete",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS" => true,
            "INFOPLIST_KEY_UIApplicationSceneManifest_Generation" => true,
            "INFOPLIST_KEY_UILaunchScreen_Generation" => true,
            "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents" => true
          }
        },
        "sources" => [
          {
            "path" => "Sources/PocketRootDemo",
            "excludes" => ["Resources"]
          }
        ],
        "resources" => [
          {"path" => "Sources/PocketRootDemo/Resources"}
        ],
        "dependencies" => [
          {"package" => "PocketRoot", "product" => "PocketRoot"},
          {"package" => "PocketRoot", "product" => "PocketRootIshRuntime"},
          {
            "package" => "PocketRoot",
            "product" => "PocketRootIshRuntimeIntegration"
          }
        ],
        "postBuildScripts" => [
          {
            "name" => "Inject reviewed development RootFS",
            "script" => "\"$SRCROOT/../../Scripts/inject-demo-rootfs.sh\"\n",
            "basedOnDependencyAnalysis" => false
          }
        ]
      },
      "PocketRootDemoTests" => {
        "type" => "bundle.unit-test",
        "platform" => "iOS",
        "deploymentTarget" => "18.0",
        "settings" => {
          "base" => {
            "ARCHS" => "arm64",
            "EXCLUDED_ARCHS[sdk=iphonesimulator*]" => "x86_64",
            "ONLY_ACTIVE_ARCH" => true
          }
        },
        "sources" => [
          {"path" => "Tests", "optional" => true}
        ],
        "resources" => [],
        "dependencies" => [
          {"target" => "PocketRootDemo"}
        ],
        "postBuildScripts" => []
      }
    }
    actual_composition = targets.to_h do |name, target|
      [
        name,
        {
          "type" => target.fetch("type"),
          "platform" => target.fetch("platform"),
          "deploymentTarget" => target.fetch("deploymentTarget"),
          "settings" => target.fetch("settings", {}),
          "sources" => target.fetch("sources", []),
          "resources" => target.fetch("resources", []),
          "dependencies" => target.fetch("dependencies", []),
          "postBuildScripts" => target.fetch("postBuildScripts", [])
        }
      ]
    end
    unless actual_composition == expected_composition
      raise ComplianceError, "project.yml target composition drifted"
    end
    {
      "name" => project.fetch("name"),
      "version" => project.dig("settings", "base", "MARKETING_VERSION"),
      "buildNumber" =>
        project.dig("settings", "base", "CURRENT_PROJECT_VERSION"),
      "minimumIOSVersion" =>
        project.dig("options", "deploymentTarget", "iOS"),
      "targets" => actual_composition.map do |name, target|
        target.merge("name" => name)
      end
    }
  rescue Psych::Exception => error
    raise ComplianceError, "project.yml is invalid YAML: #{error.message}"
  rescue KeyError, TypeError => error
    raise ComplianceError, "project.yml is incomplete: #{error.message}"
  end

  def validate_resource_files(root)
    resource_roots = [
      root.join(
        "Examples/PocketRootDemo/Sources/PocketRootDemo/Resources"
      ),
      root.join("Sources/PocketRootResources/Resources")
    ]
    actual = {}
    resource_roots.each do |directory|
      if directory.symlink? || !directory.directory?
        raise ComplianceError,
          "resource directory is not a real directory: #{directory}"
      end
      pending = directory.children
      until pending.empty?
        entry = pending.pop
        stat = entry.lstat
        if stat.symlink?
          raise ComplianceError, "resource tree contains a symlink: #{entry}"
        elsif stat.directory?
          pending.concat(entry.children)
        elsif stat.file?
          relative = entry.relative_path_from(root).to_s
          actual[relative] =
            Digest::SHA256.hexdigest(read_regular(entry, "resource #{relative}"))
        else
          raise ComplianceError,
            "resource tree contains a special entry: #{entry}"
        end
      end
    end
    unless actual == EXPECTED_RESOURCE_FILES
      raise ComplianceError, "default product resource tree drifted"
    end
    actual
  rescue Errno::ENOENT, ArgumentError => error
    raise ComplianceError, "resource tree is incomplete: #{error.message}"
  end

  def validate_rootfs(evidence, sbom, evidence_bytes, sbom_bytes)
    unless Digest::SHA256.hexdigest(evidence_bytes) ==
      ROOTFS.fetch("evidenceSha256") &&
      Digest::SHA256.hexdigest(sbom_bytes) == ROOTFS.fetch("sbomSha256")
      raise ComplianceError, "RootFS compliance evidence digest drifted"
    end
    archive = evidence.fetch("archive")
    engineering = evidence.fetch("engineeringStatus")
    unless archive.fetch("version") == ROOTFS.fetch("version") &&
      archive.fetch("url") == ROOTFS.fetch("url") &&
      archive.fetch("byteCount") == ROOTFS.fetch("byteCount") &&
      archive.fetch("sha256") == ROOTFS.fetch("sha256") &&
      engineering.fetch("machineReadableSPDXSBOM") == true &&
      engineering.fetch("sourceDeliveryCandidateMaterializerReady") == true &&
      engineering.fetch("sourceDeliveryMaterialized") == false &&
      engineering.fetch("correspondingSourceDeliveryApproved") == false &&
      engineering.fetch("completeLicenseAndNoticeBundle") == false &&
      engineering.fetch("redistributionApproved") == false
      raise ComplianceError,
        "RootFS evidence does not preserve the pinned archive and closed gates"
    end
    packages = sbom.fetch("packages")
    unless sbom.fetch("spdxVersion") == "SPDX-2.3" &&
      sbom.fetch("SPDXID") == "SPDXRef-DOCUMENT" &&
      packages.is_a?(Array) &&
      packages.length == 15 &&
      packages.map { |package| package.fetch("SPDXID") }.uniq.length ==
        packages.length
      raise ComplianceError, "RootFS SPDX SBOM has an invalid package set"
    end
    packages.each do |package|
      unless package.fetch("name").is_a?(String) &&
        package.fetch("versionInfo").is_a?(String) &&
        package.fetch("licenseDeclared").is_a?(String)
        raise ComplianceError, "RootFS SPDX package is incomplete"
      end
    end
    packages
  rescue KeyError, TypeError => error
    raise ComplianceError, "RootFS evidence is incomplete: #{error.message}"
  end

  def validate_spdx_license_list(document)
    license_ids = document.fetch("licenseIds")
    exception_ids = document.fetch("exceptionIds")
    source_files = document.fetch("sourceFiles")
    valid_identifier = /\A[A-Za-z0-9][A-Za-z0-9.-]*\z/
    valid_document =
      document.keys == %w[
        schemaVersion
        licenseListVersion
        releaseDate
        sourceRepository
        sourceRevision
        sourceFiles
        licenseIds
        exceptionIds
      ] &&
      source_files.keys == %w[
        licenses.jsonSha256
        exceptions.jsonSha256
      ] &&
      document.fetch("schemaVersion") == 1 &&
      document.fetch("licenseListVersion") ==
        SPDX_LICENSE_LIST.fetch("version") &&
      document.fetch("releaseDate") ==
        SPDX_LICENSE_LIST.fetch("releaseDate") &&
      document.fetch("sourceRepository") ==
        SPDX_LICENSE_LIST.fetch("repository") &&
      document.fetch("sourceRevision") ==
        SPDX_LICENSE_LIST.fetch("revision") &&
      source_files.fetch("licenses.jsonSha256") ==
        SPDX_LICENSE_LIST.fetch("licensesJsonSha256") &&
      source_files.fetch("exceptions.jsonSha256") ==
        SPDX_LICENSE_LIST.fetch("exceptionsJsonSha256") &&
      license_ids.is_a?(Array) &&
      license_ids.length == SPDX_LICENSE_LIST.fetch("licenseCount") &&
      license_ids == license_ids.sort &&
      license_ids.uniq.length == license_ids.length &&
      license_ids.all? do |identifier|
        identifier.is_a?(String) && identifier.match?(valid_identifier)
      end &&
      exception_ids.is_a?(Array) &&
      exception_ids.length == SPDX_LICENSE_LIST.fetch("exceptionCount") &&
      exception_ids == exception_ids.sort &&
      exception_ids.uniq.length == exception_ids.length &&
      exception_ids.all? do |identifier|
        identifier.is_a?(String) && identifier.match?(valid_identifier)
      end
    unless valid_document
      raise ComplianceError,
        "pinned SPDX license and exception identifier set is invalid"
    end
    true
  rescue KeyError, TypeError => error
    raise ComplianceError, "SPDX license list is incomplete: #{error.message}"
  end

  def spdx_expression_tokens(expression)
    return nil unless expression.is_a?(String)
    return nil if expression.empty? || expression.bytesize > 1_024

    tokens = []
    offset = 0
    while offset < expression.length
      remaining = expression[offset..]
      if (match = remaining.match(/\A\s+/))
        offset += match[0].length
      elsif %w[( )].include?(remaining[0])
        tokens << remaining[0]
        offset += 1
      elsif (match = remaining.match(/\A[A-Za-z0-9][A-Za-z0-9.-]*/))
        tokens << match[0]
        offset += match[0].length
      else
        return nil
      end
    end
    tokens.empty? ? nil : tokens
  end

  def valid_spdx_license_expression?(expression, license_list)
    tokens = spdx_expression_tokens(expression)
    return false if tokens.nil?

    license_ids = license_list.fetch("licenseIds")
    exception_ids = license_list.fetch("exceptionIds")
    depth = 0
    expect_operand = true
    expect_exception = false
    last_was_license = false
    tokens.each do |token|
      if expect_exception
        return false unless exception_ids.include?(token)

        expect_exception = false
        expect_operand = false
        last_was_license = false
      elsif expect_operand
        if token == "("
          depth += 1
          last_was_license = false
        elsif license_ids.include?(token)
          expect_operand = false
          last_was_license = true
        else
          return false
        end
      elsif token == "WITH"
        return false unless last_was_license

        expect_exception = true
        last_was_license = false
      elsif %w[AND OR].include?(token)
        expect_operand = true
        last_was_license = false
      elsif token == ")"
        return false if depth.zero?

        depth -= 1
        last_was_license = false
      else
        return false
      end
    end
    !expect_operand && !expect_exception && depth.zero?
  rescue KeyError, TypeError
    false
  end

  def validate_release_decisions(document, license_list)
    source = document.fetch("sourceRelease")
    runtime = document.fetch("runtimeDistribution")
    approval = document.fetch("approval")
    boolean = lambda do |value|
      value.instance_of?(TrueClass) || value.instance_of?(FalseClass)
    end
    source_authorized = source.fetch("sourceReleaseAuthorized")
    runtime_authorized = runtime.fetch("distributionAuthorized")
    expected_status =
      if source_authorized && runtime_authorized
        "source-and-runtime-distribution-authorized"
      elsif source_authorized
        "source-release-authorized"
      elsif runtime_authorized
        "runtime-distribution-authorized"
      else
        "no-release-authorization-granted"
      end
    valid_spdx =
      source.fetch("topLevelLicenseSpdx").nil? ||
        valid_spdx_license_expression?(
          source.fetch("topLevelLicenseSpdx"),
          license_list
        )
    final_artifact_sha256 =
      runtime.fetch("finalArtifactSha256")
    valid_final_artifact_sha256 =
      final_artifact_sha256.nil? ||
        (
          final_artifact_sha256.is_a?(String) &&
            final_artifact_sha256.match?(HASH_PATTERN)
        )
    decision_values = [
      source.fetch("contributorPolicyApproved"),
      source.fetch("releaseNoticeApproved"),
      source_authorized,
      runtime.fetch("rootFSBundlingApproved"),
      runtime.fetch("completeLicenseAndNoticeBundleApproved"),
      runtime.fetch("correspondingSourceDeliveryApproved"),
      runtime.fetch("appStorePolicyApproved"),
      runtime.fetch("privacyReviewApproved"),
      runtime.fetch("legalReviewApproved"),
      runtime_authorized
    ]
    has_reviewed_decision =
      !source.fetch("topLevelLicenseSpdx").nil? ||
        !final_artifact_sha256.nil? ||
        decision_values.any?
    approval_identity_valid =
      approval.fetch("approvedBy").is_a?(String) &&
        !approval.fetch("approvedBy").strip.empty?
    approval_time_valid =
      approval.fetch("approvedAt").is_a?(String) &&
        approval.fetch("approvedAt").match?(
          /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/
        ) &&
        Time.iso8601(approval.fetch("approvedAt")).utc.iso8601 ==
          approval.fetch("approvedAt")
    approval_metadata_valid =
      if has_reviewed_decision
        approval_identity_valid && approval_time_valid
      else
        approval.fetch("approvedBy").nil? &&
          approval.fetch("approvedAt").nil?
      end
    valid_schema =
      document.keys == %w[
        schemaVersion
        releaseVersion
        status
        sourceRelease
        runtimeDistribution
        approval
      ] &&
      source.keys == %w[
        topLevelLicenseSpdx
        contributorPolicyApproved
        releaseNoticeApproved
        sourceReleaseAuthorized
      ] &&
      runtime.keys == %w[
        rootFSDeliveryModel
        rootFSBundlingApproved
        finalArtifactSha256
        completeLicenseAndNoticeBundleApproved
        correspondingSourceDeliveryApproved
        appStorePolicyApproved
        privacyReviewApproved
        legalReviewApproved
        distributionAuthorized
      ] &&
      approval.keys == %w[approvedBy approvedAt notes] &&
      document.fetch("schemaVersion") == 1 &&
      document.fetch("releaseVersion") == RELEASE_VERSION &&
      document.fetch("status") == expected_status &&
      runtime.fetch("rootFSDeliveryModel") ==
        "caller-provided-local-input" &&
      decision_values.all?(&boolean) &&
      valid_spdx &&
      valid_final_artifact_sha256 &&
      approval.fetch("notes").is_a?(String) &&
      !approval.fetch("notes").strip.empty? &&
      approval_metadata_valid
    source_authorization_valid =
      !source_authorized ||
        (
          !source.fetch("topLevelLicenseSpdx").nil? &&
            source.fetch("contributorPolicyApproved") &&
            source.fetch("releaseNoticeApproved")
        )
    runtime_authorization_valid =
      !runtime_authorized ||
        (
          !source.fetch("topLevelLicenseSpdx").nil? &&
            runtime.fetch("rootFSBundlingApproved") == false &&
            !final_artifact_sha256.nil? &&
            runtime.fetch("completeLicenseAndNoticeBundleApproved") &&
            runtime.fetch("correspondingSourceDeliveryApproved") &&
            runtime.fetch("appStorePolicyApproved") &&
            runtime.fetch("privacyReviewApproved") &&
            runtime.fetch("legalReviewApproved")
        )
    unless valid_schema &&
      source_authorization_valid &&
      runtime_authorization_valid
      raise ComplianceError,
        "release decisions violate the reviewed authorization schema or " \
        "fail-closed invariants"
    end
    true
  rescue ArgumentError, KeyError, TypeError => error
    raise ComplianceError, "release decisions are invalid: #{error.message}"
  end

  def validate_source_license_decision(document)
    license = document.dig("sourceRelease", "topLevelLicenseSpdx")
    unless license.nil? || license == "MIT"
      raise ComplianceError,
        "source release decision must match the approved MIT license"
    end
    true
  end

  def final_artifact_rootfs_asset_paths(inventory)
    rootfs_component = lambda do |component|
      normalized = component.downcase
      normalized.match?(
        /(?:\A|[._-])(?:rootfs|fakefs)(?:\z|[._-])/
      ) ||
        normalized.match?(
          /(?:\A|[._-])pocketroot[._-]fs(?:\z|[._-])/
        )
    end
    matches = []
    inventory.fetch("directories").each do |directory|
      path =
        PocketRootReleaseArtifactScanner.safe_relative_path(
          directory.fetch("path"),
          "final artifact directory path"
        )
      components = path.each_filename.map(&:downcase)
      matches << path.to_s if components.any?(&rootfs_component)
    end
    inventory.fetch("files").each do |file|
      path =
        PocketRootReleaseArtifactScanner.safe_relative_path(
          file.fetch("path"),
          "final artifact file path"
        )
      basename = path.basename.to_s.downcase
      components = path.each_filename.map(&:downcase)
      rootfs_name = rootfs_component.call(basename)
      archive_name =
        basename == ROOTFS.fetch("filename").downcase ||
          basename.match?(
            /\.(?:tar(?:\.(?:gz|xz|bz2|zst))?|tgz|zip|cpio(?:\.gz)?|img|squashfs)\z/
          )
      known_payload =
        file.fetch("sha256") == ROOTFS.fetch("sha256") ||
          file.fetch("byteCount") == ROOTFS.fetch("byteCount")
      if rootfs_name ||
        archive_name ||
        known_payload ||
        components.any?(&rootfs_component)
        matches << path.to_s
      end
    end
    matches.uniq.sort
  rescue KeyError, TypeError => error
    raise ComplianceError,
      "final artifact RootFS exclusion evidence is incomplete: #{error.message}"
  end

  def load_final_artifact_evidence(root)
    directory = root.join(FINAL_ARTIFACT_EVIDENCE_RELATIVE)
    absent = {
      "status" => "not-provided",
      "evidenceDirectory" => FINAL_ARTIFACT_EVIDENCE_RELATIVE,
      "inventoryPath" => FINAL_ARTIFACT_INVENTORY_RELATIVE,
      "inventorySha256" => nil,
      "sbomPath" => FINAL_ARTIFACT_SBOM_RELATIVE,
      "sbomSha256" => nil,
      "artifactSha256" => nil,
      "inputKind" => nil,
      "releaseSignatureValid" => false,
      "rootFSExcluded" => false,
      "rootFSAssetPaths" => []
    }
    return [absent, {}] unless directory.exist? || directory.symlink?

    if directory.symlink? || !directory.lstat.directory?
      raise ComplianceError,
        "final artifact evidence must be a real directory: #{directory}"
    end
    resolved_root = root.realpath
    resolved_directory = directory.realpath
    unless resolved_directory.to_s.start_with?(
      "#{resolved_root}#{File::SEPARATOR}"
    )
      raise ComplianceError,
        "final artifact evidence escapes the repository root"
    end
    expected_files = %w[ARTIFACT-INVENTORY.json SBOM.spdx.json]
    actual_files = directory.children.map do |path|
      path.basename.to_s
    end.sort
    unless actual_files == expected_files
      raise ComplianceError,
        "final artifact evidence file set drifted: #{actual_files.inspect}"
    end
    inventory, inventory_bytes =
      load_json(
        root.join(FINAL_ARTIFACT_INVENTORY_RELATIVE),
        "final artifact inventory"
      )
    sbom, sbom_bytes =
      load_json(
        root.join(FINAL_ARTIFACT_SBOM_RELATIVE),
        "final artifact SPDX SBOM"
      )
    PocketRootReleaseArtifactScanner.validate_inventory(inventory)
    PocketRootReleaseArtifactScanner.validate_sbom(sbom, inventory)
    artifact_sha256 = inventory.dig("artifact", "sha256")
    unless artifact_sha256.is_a?(String) &&
      artifact_sha256.match?(HASH_PATTERN)
      raise ComplianceError,
        "final artifact inventory has an invalid artifact SHA-256"
    end
    rootfs_asset_paths = final_artifact_rootfs_asset_paths(inventory)
    inventory_sha256 = Digest::SHA256.hexdigest(inventory_bytes)
    sbom_sha256 = Digest::SHA256.hexdigest(sbom_bytes)
    summary = {
      "status" => "engineering-evidence-only",
      "evidenceDirectory" => FINAL_ARTIFACT_EVIDENCE_RELATIVE,
      "inventoryPath" => FINAL_ARTIFACT_INVENTORY_RELATIVE,
      "inventorySha256" => inventory_sha256,
      "sbomPath" => FINAL_ARTIFACT_SBOM_RELATIVE,
      "sbomSha256" => sbom_sha256,
      "artifactSha256" => artifact_sha256,
      "inputKind" => inventory.dig("input", "kind"),
      "releaseSignatureValid" => false,
      "rootFSExcluded" => false,
      "rootFSAssetPaths" => rootfs_asset_paths
    }
    evidence_sha256 = {
      FINAL_ARTIFACT_INVENTORY_RELATIVE => inventory_sha256,
      FINAL_ARTIFACT_SBOM_RELATIVE => sbom_sha256
    }
    [summary, evidence_sha256]
  rescue PocketRootReleaseArtifactScanner::ScanError => error
    raise ComplianceError,
      "final artifact evidence failed scanner validation: #{error.message}"
  end

  def collect_inputs(root = repository_root)
    package_swift =
      read_regular(root.join("Package.swift"), "Package.swift")
    package_resolved, package_resolved_bytes =
      load_json(root.join("Package.resolved"), "Package.resolved")
    project_bytes =
      read_regular(
        root.join("Examples/PocketRootDemo/project.yml"),
        "PocketRoot Demo project.yml"
      )
    host_project_bytes =
      read_regular(
        root.join("Examples/PocketRootHostApp/project.yml"),
        "Host App project.yml"
      )
    quick_start_project_bytes =
      read_regular(
        root.join("Examples/PocketRootQuickStartApp/project.yml"),
        "Quick Start App project.yml"
      )
    external_consumer_project_bytes =
      read_regular(
        root.join(
          "Tests/Integration/ExternalConsumerApp/project.yml.template"
        ),
        "External Consumer App project template"
      )
    license_bytes = read_regular(root.join("LICENSE"), "LICENSE")
    notice_bytes = read_regular(root.join("NOTICE.md"), "NOTICE.md")
    contributing_bytes =
      read_regular(root.join("CONTRIBUTING.md"), "CONTRIBUTING.md")
    contributing_english_bytes =
      read_regular(root.join("CONTRIBUTING.en.md"), "CONTRIBUTING.en.md")
    release_decisions, release_decisions_bytes =
      load_json(
        root.join("Compliance/Release/RELEASE-DECISIONS.json"),
        "release decisions"
      )
    spdx_license_list, spdx_license_list_bytes =
      load_json(
        root.join(SPDX_LICENSE_LIST.fetch("path")),
        "pinned SPDX license list"
      )
    demo_rootfs_injection_bytes =
      read_regular(
        root.join("Scripts/inject-demo-rootfs.sh"),
        "Demo RootFS injection script"
      )
    release_artifact_scanner_bytes =
      read_regular(
        root.join("Scripts/scan-release-artifact.rb"),
        "release artifact scanner"
      )
    host_app_ui_smoke_bytes =
      read_regular(
        root.join("Scripts/run-host-app-ui-smoke.sh"),
        "Host App UI smoke script"
      )
    example_ui_smoke_bytes =
      read_regular(
        root.join("Scripts/run-ios-example-ui-smoke.sh"),
        "Shared example UI smoke script"
      )
    quick_start_ui_smoke_bytes =
      read_regular(
        root.join("Scripts/run-quick-start-ui-smoke.sh"),
        "Quick Start UI smoke script"
      )
    external_consumer_ui_smoke_bytes =
      read_regular(
        root.join("Scripts/run-external-consumer-ui-smoke.sh"),
        "External Consumer UI smoke script"
      )
    host_app_device_ui_smoke_bytes =
      read_regular(
        root.join("Scripts/run-host-app-device-ui-smoke.sh"),
        "Host App physical-device UI smoke script"
      )
    swiftterm_notice_bytes =
      read_regular(
        root.join(SWIFTTERM.fetch("noticePath")),
        "SwiftTerm license notice"
      )
    implementation_files = implementation_file_sha256(root)
    resource_files = validate_resource_files(root)
    rootfs_directory = root.join("Compliance/RootFS/v0.3.3")
    rootfs_evidence, rootfs_evidence_bytes =
      load_json(rootfs_directory.join("EVIDENCE.json"), "RootFS evidence")
    rootfs_sbom, rootfs_sbom_bytes =
      load_json(rootfs_directory.join("SBOM.spdx.json"), "RootFS SPDX SBOM")
    final_artifact_evidence, final_artifact_file_sha256 =
      load_final_artifact_evidence(root)

    unless license_bytes == MIT_LICENSE_TEXT
      raise ComplianceError,
        "PocketRoot LICENSE no longer matches the approved MIT license"
    end
    unless notice_bytes.include?(
      "does not cover or relicense third-party components".b
    ) &&
      contributing_bytes.include?("MIT License".b) &&
      contributing_english_bytes.include?(
        "provided under the same MIT License".b
      )
      raise ComplianceError,
        "source release notice or contributor policy drifted"
    end
    validate_spdx_license_list(spdx_license_list)
    validate_release_decisions(release_decisions, spdx_license_list)
    validate_source_license_decision(release_decisions)

    package = parse_package_manifest(package_swift)
    resolved = parse_package_resolved(package_resolved)
    project = parse_project(project_bytes)
    rootfs_packages =
      validate_rootfs(
        rootfs_evidence,
        rootfs_sbom,
        rootfs_evidence_bytes,
        rootfs_sbom_bytes
      )
    file_sha256 = {
      "LICENSE" => Digest::SHA256.hexdigest(license_bytes),
      "NOTICE.md" => Digest::SHA256.hexdigest(notice_bytes),
      "CONTRIBUTING.md" => Digest::SHA256.hexdigest(contributing_bytes),
      "CONTRIBUTING.en.md" =>
        Digest::SHA256.hexdigest(contributing_english_bytes),
      SPDX_LICENSE_LIST.fetch("path") =>
        Digest::SHA256.hexdigest(spdx_license_list_bytes),
      "Compliance/Release/RELEASE-DECISIONS.json" =>
        Digest::SHA256.hexdigest(release_decisions_bytes),
      "Package.resolved" => Digest::SHA256.hexdigest(package_resolved_bytes),
      "Package.swift" => Digest::SHA256.hexdigest(package_swift),
      "Examples/PocketRootDemo/project.yml" =>
        Digest::SHA256.hexdigest(project_bytes),
      "Examples/PocketRootHostApp/project.yml" =>
        Digest::SHA256.hexdigest(host_project_bytes),
      "Examples/PocketRootQuickStartApp/project.yml" =>
        Digest::SHA256.hexdigest(quick_start_project_bytes),
      "Tests/Integration/ExternalConsumerApp/project.yml.template" =>
        Digest::SHA256.hexdigest(external_consumer_project_bytes),
      "Scripts/inject-demo-rootfs.sh" =>
        Digest::SHA256.hexdigest(demo_rootfs_injection_bytes),
      "Scripts/scan-release-artifact.rb" =>
        Digest::SHA256.hexdigest(release_artifact_scanner_bytes),
      "Scripts/run-host-app-ui-smoke.sh" =>
        Digest::SHA256.hexdigest(host_app_ui_smoke_bytes),
      "Scripts/run-ios-example-ui-smoke.sh" =>
        Digest::SHA256.hexdigest(example_ui_smoke_bytes),
      "Scripts/run-quick-start-ui-smoke.sh" =>
        Digest::SHA256.hexdigest(quick_start_ui_smoke_bytes),
      "Scripts/run-external-consumer-ui-smoke.sh" =>
        Digest::SHA256.hexdigest(external_consumer_ui_smoke_bytes),
      "Scripts/run-host-app-device-ui-smoke.sh" =>
        Digest::SHA256.hexdigest(host_app_device_ui_smoke_bytes),
      SWIFTTERM.fetch("noticePath") =>
        Digest::SHA256.hexdigest(swiftterm_notice_bytes)
    }
    unless file_sha256 == EXPECTED_REPOSITORY_FILES
      raise ComplianceError,
        "versioned release-composition repository input digest drifted"
    end
    file_sha256.merge!(implementation_files)
    file_sha256.merge!(resource_files)
    file_sha256.merge!(final_artifact_file_sha256)
    file_sha256["Compliance/RootFS/v0.3.3/EVIDENCE.json"] =
      Digest::SHA256.hexdigest(rootfs_evidence_bytes)
    file_sha256["Compliance/RootFS/v0.3.3/SBOM.spdx.json"] =
      Digest::SHA256.hexdigest(rootfs_sbom_bytes)
    {
      package: package,
      resolved: resolved,
      project: project,
      rootfs_evidence: rootfs_evidence,
      rootfs_sbom: rootfs_sbom,
      rootfs_packages: rootfs_packages,
      final_artifact_evidence: final_artifact_evidence,
      release_decisions: release_decisions,
      spdx_license_list: spdx_license_list,
      file_sha256: file_sha256
    }
  end

  def composition(inputs)
    package = inputs.fetch(:package)
    project = inputs.fetch(:project)
    rootfs_packages = inputs.fetch(:rootfs_packages)
    {
      "schemaVersion" => 1,
      "generatedAt" => GENERATED_AT,
      "release" => {
        "name" => "PocketRoot",
        "version" => RELEASE_VERSION,
        "buildNumber" => project.fetch("buildNumber"),
        "status" =>
          "experimental-engineering-composition-not-distribution-candidate",
        "minimumIOSVersion" => project.fetch("minimumIOSVersion")
      },
      "repositoryEvidence" => inputs.fetch(:file_sha256),
      "swiftPackage" => package,
      "application" => project,
      "finalArtifactEvidence" =>
        inputs.fetch(:final_artifact_evidence),
      "profiles" => [
        {
          "id" => "default-demo",
          "rootTarget" => "PocketRootDemo",
          "swiftProducts" => %w[
            PocketRoot
            PocketRootIshRuntime
            PocketRootIshRuntimeIntegration
          ],
          "includesIshRuntime" => true,
          "requiresExternalRootFS" => true,
          "artifactBuiltAndScanned" => false
        },
        {
          "id" => "native-runtime-smoke",
          "rootTarget" => "PocketRootIshRuntimeSmoke",
          "swiftProducts" =>
            %w[
              PocketRootCore
              PocketRootIshRuntimeIntegration
              PocketRootResources
            ],
          "includesIshRuntime" => true,
          "requiresExternalRootFS" => true,
          "artifactBuiltAndScanned" => false
        },
        {
          "id" => "standalone-host-example",
          "rootTarget" => "PocketRootHostApp",
          "swiftProducts" => %w[
            PocketRoot
            PocketRootIshRuntimeIntegration
          ],
          "includesIshRuntime" => true,
          "requiresExternalRootFS" => true,
          "artifactBuiltAndScanned" => false
        },
        {
          "id" => "two-entry-quick-start-example",
          "rootTarget" => "PocketRootQuickStartApp",
          "swiftProducts" => %w[
            PocketRoot
            PocketRootIshRuntimeIntegration
          ],
          "includesIshRuntime" => true,
          "requiresExternalRootFS" => true,
          "artifactBuiltAndScanned" => false
        },
        {
          "id" => "external-consumer-acceptance",
          "rootTarget" => "PocketRootExternalConsumerApp",
          "swiftProducts" => %w[
            PocketRoot
            PocketRootIshRuntimeIntegration
          ],
          "includesIshRuntime" => true,
          "requiresExternalRootFS" => true,
          "artifactBuiltAndScanned" => false
        },
        {
          "id" => "swift-package-all-products",
          "rootTarget" => nil,
          "swiftProducts" =>
            package.fetch("products").map { |product| product.fetch("name") },
          "includesIshRuntime" => true,
          "requiresExternalRootFS" => false,
          "artifactBuiltAndScanned" => false
        }
      ],
      "externalComponents" => {
        "ishEmbed" => ISHEMBED,
        "swiftTerm" => SWIFTTERM,
        "swiftArgumentParser" => SWIFT_ARGUMENT_PARSER,
        "rootFS" => ROOTFS.merge(
          "deliveryModel" => "caller-provided-local-input",
          "bundledByDefault" => false,
          "downloadedByLibrary" => false,
          "installedPackageCount" => rootfs_packages.length,
          "packageSBOMPath" => "Compliance/RootFS/v0.3.3/SBOM.spdx.json"
        ),
        "appleSystemLibraries" => [
          {
            "name" => "libsqlite3",
            "redistributedByPocketRoot" => false
          },
          {
            "name" => "libz",
            "redistributedByPocketRoot" => false
          }
        ]
      },
      "coverage" => {
        "swiftProductInventoryComplete" => true,
        "applicationTargetInventoryComplete" => true,
        "externalDependencyPinsComplete" => true,
        "rootFSPackageSBOMEmbedded" => true,
        "releaseCompositionSBOMGenerated" => true,
        "releaseArtifactBuilt" => false,
        "releaseArtifactScanned" => false,
        "binaryFilesAnalyzed" => false,
        "completeReleaseArtifactSBOM" => false,
        "topLevelLicenseFinalized" => true,
        "completeLicenseAndNoticeBundle" => false,
        "correspondingSourceDeliveryApproved" => false,
        "appStorePolicyApproved" => false,
        "legalReviewApproved" => false,
        "distributionAuthorized" => false
      }
    }
  end

  def readiness_gate(
    id:,
    title:,
    title_zh:,
    satisfied:,
    evidence:,
    owner:,
    action:
  )
    {
      "id" => id,
      "title" => title,
      "titleZh" => title_zh,
      "satisfied" => satisfied,
      "evidence" => evidence,
      "owner" => owner,
      "requiredAction" => action
    }
  end

  def next_required_decision(blocked_gate)
    return nil if blocked_gate.nil?

    {
      "id" =>
        %w[
          top-level-license-finalized
          runtime-top-level-license-finalized
        ].include?(blocked_gate.fetch("id")) ?
          "select-top-level-license" : blocked_gate.fetch("id"),
      "owner" => blocked_gate.fetch("owner"),
      "reason" => blocked_gate.fetch("requiredAction")
    }
  end

  def readiness(composition_document, inputs)
    coverage = composition_document.fetch("coverage")
    rootfs = composition_document.dig("externalComponents", "rootFS")
    final_artifact =
      composition_document.fetch("finalArtifactEvidence")
    decisions = inputs.fetch(:release_decisions)
    source_decisions = decisions.fetch("sourceRelease")
    runtime_decisions = decisions.fetch("runtimeDistribution")
    final_artifact_identity_matches_review =
      !runtime_decisions.fetch("finalArtifactSha256").nil? &&
        final_artifact.fetch("artifactSha256") ==
          runtime_decisions.fetch("finalArtifactSha256")
    source_gates = [
      readiness_gate(
        id: "source-boundary-excludes-rootfs",
        title: "Source release excludes the RootFS payload",
        title_zh: "源码发布不包含 RootFS 载荷",
        satisfied:
          rootfs.fetch("bundledByDefault") == false &&
            rootfs.fetch("downloadedByLibrary") == false,
        evidence:
          "COMPOSITION.json externalComponents.rootFS bundledByDefault=false " \
          "and downloadedByLibrary=false",
        owner: "engineering",
        action:
          "Keep the RootFS outside Git, SwiftPM resources, and source-release " \
          "assets."
      ),
      readiness_gate(
        id: "public-api-status-declared",
        title: "Public API status is declared experimental",
        title_zh: "公共 API 状态已声明为 Experimental",
        satisfied:
          composition_document.dig("release", "status") ==
            "experimental-engineering-composition-not-distribution-candidate",
        evidence: "COMPOSITION.json release.status",
        owner: "engineering",
        action:
          "Keep the Experimental label until a separately reviewed stability " \
          "decision is recorded."
      ),
      readiness_gate(
        id: "top-level-license-finalized",
        title: "Top-level PocketRoot license is finalized",
        title_zh: "PocketRoot 顶层许可证已确定",
        satisfied:
          coverage.fetch("topLevelLicenseFinalized") &&
            !source_decisions.fetch("topLevelLicenseSpdx").nil?,
        evidence: "LICENSE and Compliance/Release/RELEASE-DECISIONS.json",
        owner: "project-owner",
        action:
          "Select an SPDX license and replace the current no-permission " \
          "placeholder with its complete terms."
      ),
      readiness_gate(
        id: "contributor-policy-approved",
        title: "Contributor and copyright policy is approved",
        title_zh: "贡献者与版权政策已批准",
        satisfied:
          source_decisions.fetch("contributorPolicyApproved"),
        evidence: "Compliance/Release/RELEASE-DECISIONS.json",
        owner: "project-owner",
        action:
          "Record the contributor, copyright, and inbound-license policy."
      ),
      readiness_gate(
        id: "release-notice-approved",
        title: "Source-release notice is approved",
        title_zh: "源码发行 NOTICE 已批准",
        satisfied: source_decisions.fetch("releaseNoticeApproved"),
        evidence: "Compliance/Release/RELEASE-DECISIONS.json",
        owner: "project-owner",
        action:
          "Approve the release notice covering PocketRoot and referenced " \
          "third-party source dependencies."
      ),
      readiness_gate(
        id: "source-release-authorized",
        title: "PocketRoot source release is explicitly authorized",
        title_zh: "PocketRoot 源码发布已明确授权",
        satisfied: source_decisions.fetch("sourceReleaseAuthorized"),
        evidence: "Compliance/Release/RELEASE-DECISIONS.json",
        owner: "project-owner",
        action:
          "Record the approving owner and date after every source-release " \
          "gate is satisfied."
      )
    ]
    runtime_gates = [
      readiness_gate(
        id: "runtime-top-level-license-finalized",
        title: "Top-level PocketRoot license is finalized for runtime distribution",
        title_zh: "Runtime 分发使用的 PocketRoot 顶层许可证已确定",
        satisfied:
          coverage.fetch("topLevelLicenseFinalized") &&
            !source_decisions.fetch("topLevelLicenseSpdx").nil?,
        evidence: "LICENSE and Compliance/Release/RELEASE-DECISIONS.json",
        owner: "project-owner",
        action:
          "Select an SPDX license and replace the current no-permission " \
          "placeholder before distributing any runtime binary or App."
      ),
      readiness_gate(
        id: "rootfs-external-input-boundary",
        title: "RootFS remains a caller-provided local input",
        title_zh: "RootFS 保持为调用方提供的本地输入",
        satisfied:
          rootfs.fetch("deliveryModel") ==
            runtime_decisions.fetch("rootFSDeliveryModel") &&
            runtime_decisions.fetch("rootFSBundlingApproved") == false &&
            final_artifact_identity_matches_review &&
            final_artifact.fetch("releaseSignatureValid") &&
            final_artifact.fetch("rootFSExcluded"),
        evidence:
          "COMPOSITION.json finalArtifactEvidence, " \
          "ARTIFACT-INVENTORY.json, SBOM.spdx.json, and release decisions",
        owner: "engineering",
        action:
          "Scan the exact final artifact, record its reviewed SHA-256, and " \
          "verify its inventory contains no RootFS payload."
      ),
      readiness_gate(
        id: "release-artifact-built-and-scanned",
        title: "Final signed and exported artifact is built and scanned",
        title_zh: "最终签名导出制品已构建并扫描",
        satisfied:
          coverage.fetch("releaseArtifactBuilt") &&
            coverage.fetch("releaseArtifactScanned") &&
            coverage.fetch("binaryFilesAnalyzed") &&
            coverage.fetch("completeReleaseArtifactSBOM") &&
            final_artifact_identity_matches_review &&
            final_artifact.fetch("releaseSignatureValid"),
        evidence:
          "COMPOSITION.json coverage and finalArtifactEvidence bound to " \
          "the reviewed artifact SHA-256",
        owner: "engineering",
        action:
          "Build the final signed/exported artifact and generate its complete " \
          "file inventory, binary scan, entitlements, and SBOM."
      ),
      readiness_gate(
        id: "complete-license-notice-bundle-approved",
        title: "Complete LICENSE and NOTICE bundle is approved",
        title_zh: "完整 LICENSE 与 NOTICE 交付包已批准",
        satisfied:
          coverage.fetch("completeLicenseAndNoticeBundle") &&
            runtime_decisions.fetch(
              "completeLicenseAndNoticeBundleApproved"
            ),
        evidence:
          "COMPOSITION.json, RootFS review evidence, and release decisions",
        owner: "legal-compliance",
        action:
          "Complete and approve the distribution LICENSE/NOTICE set, including " \
          "the remaining alpine-keys material decision."
      ),
      readiness_gate(
        id: "corresponding-source-delivery-approved",
        title: "Corresponding-source delivery is approved",
        title_zh: "对应源码交付已批准",
        satisfied:
          coverage.fetch("correspondingSourceDeliveryApproved") &&
            runtime_decisions.fetch(
              "correspondingSourceDeliveryApproved"
            ),
        evidence:
          "COMPOSITION.json, RootFS source evidence, and release decisions",
        owner: "legal-compliance",
        action:
          "Materialize, verify, and approve the corresponding-source delivery " \
          "and source-offer mechanism."
      ),
      readiness_gate(
        id: "app-store-policy-approved",
        title: "App Store executable-code policy is approved",
        title_zh: "App Store 可执行代码策略已批准",
        satisfied:
          coverage.fetch("appStorePolicyApproved") &&
            runtime_decisions.fetch("appStorePolicyApproved"),
        evidence: "COMPOSITION.json and release decisions",
        owner: "product-legal",
        action:
          "Approve the written policy for shell, network, apk, downloaded code, " \
          "and App Review disclosure."
      ),
      readiness_gate(
        id: "privacy-review-approved",
        title: "Runtime privacy and data-lifecycle review is approved",
        title_zh: "Runtime 隐私与数据生命周期评审已批准",
        satisfied: runtime_decisions.fetch("privacyReviewApproved"),
        evidence: "Compliance/Release/RELEASE-DECISIONS.json",
        owner: "product-privacy",
        action:
          "Approve storage, backup exclusion, logs, network, secrets, deletion, " \
          "and privacy-manifest behavior."
      ),
      readiness_gate(
        id: "runtime-legal-review-approved",
        title: "Complete runtime distribution legal review is approved",
        title_zh: "完整 Runtime 分发法律评审已批准",
        satisfied:
          coverage.fetch("legalReviewApproved") &&
            runtime_decisions.fetch("legalReviewApproved"),
        evidence: "COMPOSITION.json and release decisions",
        owner: "legal-compliance",
        action:
          "Approve the combined PocketRoot, IshEmbed/iSH, SwiftTerm, RootFS, " \
          "and final-artifact distribution composition."
      ),
      readiness_gate(
        id: "runtime-distribution-authorized",
        title: "Runtime binary/App distribution is explicitly authorized",
        title_zh: "Runtime 二进制/App 分发已明确授权",
        satisfied:
          coverage.fetch("distributionAuthorized") &&
            runtime_decisions.fetch("distributionAuthorized"),
        evidence: "COMPOSITION.json and release decisions",
        owner: "project-owner",
        action:
          "Record the approving owner and date only after every runtime " \
          "distribution gate is satisfied."
      )
    ]
    tracks = {
      "sourcePackageRelease" => {
        "scope" =>
          "PocketRoot source and Swift Package metadata only; no RootFS, " \
          "XCFramework mirror, App, archive, IPA, or binary SDK asset.",
        "status" =>
          source_gates.all? { |gate| gate.fetch("satisfied") } ?
            "ready" : "blocked",
        "gates" => source_gates
      },
      "runtimeDistribution" => {
        "scope" =>
          "Any App, binary SDK, TestFlight/App Store build, or redistributed " \
          "runtime artifact; excludes every RootFS asset, which remains a " \
          "caller-provided local input.",
        "status" =>
          runtime_gates.all? { |gate| gate.fetch("satisfied") } ?
            "ready" : "blocked",
        "gates" => runtime_gates
      }
    }
    blocked_gate_ids =
      tracks.values.flat_map do |track|
        track.fetch("gates").reject do |gate|
          gate.fetch("satisfied")
        end.map { |gate| gate.fetch("id") }
      end
    {
      "schemaVersion" => 1,
      "generatedAt" => GENERATED_AT,
      "releaseVersion" => RELEASE_VERSION,
      "overallStatus" =>
        tracks.values.all? { |track| track.fetch("status") == "ready" } ?
          "ready" : "blocked",
      "authorizationSource" =>
        "Compliance/Release/RELEASE-DECISIONS.json",
      "tracks" => tracks,
      "blockedGateIds" => blocked_gate_ids,
      "nextRequiredDecision" =>
        next_required_decision(
          tracks.values.flat_map { |track| track.fetch("gates") }.find do |gate|
            !gate.fetch("satisfied")
          end
        ),
      "warning" =>
        "Engineering validation is not distribution authorization. A ready " \
        "source track would not authorize runtime, RootFS, App, or binary " \
        "distribution."
    }
  end

  def validate_readiness(document)
    tracks = document.fetch("tracks")
    source = tracks.fetch("sourcePackageRelease")
    runtime = tracks.fetch("runtimeDistribution")
    source_ids = source.fetch("gates").map { |gate| gate.fetch("id") }
    runtime_ids = runtime.fetch("gates").map { |gate| gate.fetch("id") }
    expected_source_ids = %w[
      source-boundary-excludes-rootfs
      public-api-status-declared
      top-level-license-finalized
      contributor-policy-approved
      release-notice-approved
      source-release-authorized
    ]
    expected_runtime_ids = %w[
      runtime-top-level-license-finalized
      rootfs-external-input-boundary
      release-artifact-built-and-scanned
      complete-license-notice-bundle-approved
      corresponding-source-delivery-approved
      app-store-policy-approved
      privacy-review-approved
      runtime-legal-review-approved
      runtime-distribution-authorized
    ]
    all_gates = source.fetch("gates") + runtime.fetch("gates")
    expected_blocked =
      all_gates.reject do |gate|
        gate.fetch("satisfied")
      end.map { |gate| gate.fetch("id") }
    expected_source_status =
      source.fetch("gates").all? { |gate| gate.fetch("satisfied") } ?
        "ready" : "blocked"
    expected_runtime_status =
      runtime.fetch("gates").all? { |gate| gate.fetch("satisfied") } ?
        "ready" : "blocked"
    expected_overall_status =
      [expected_source_status, expected_runtime_status].all? do |status|
        status == "ready"
      end ? "ready" : "blocked"
    expected_next_decision =
      next_required_decision(
        all_gates.find { |gate| !gate.fetch("satisfied") }
      )
    valid_gate_shapes =
      all_gates.all? do |gate|
        gate.keys == %w[
          id
          title
          titleZh
          satisfied
          evidence
          owner
          requiredAction
        ] &&
          (
            gate.fetch("satisfied").instance_of?(TrueClass) ||
              gate.fetch("satisfied").instance_of?(FalseClass)
          ) &&
          %w[title titleZh evidence owner requiredAction].all? do |key|
            gate.fetch(key).is_a?(String) && !gate.fetch(key).empty?
          end
      end
    valid_document =
      document.keys == %w[
        schemaVersion
        generatedAt
        releaseVersion
        overallStatus
        authorizationSource
        tracks
        blockedGateIds
        nextRequiredDecision
        warning
      ] &&
      source.keys == %w[scope status gates] &&
      runtime.keys == %w[scope status gates] &&
      document.fetch("schemaVersion") == 1 &&
      document.fetch("generatedAt") == GENERATED_AT &&
      document.fetch("releaseVersion") == RELEASE_VERSION &&
      document.fetch("overallStatus") == expected_overall_status &&
      document.fetch("authorizationSource") ==
        "Compliance/Release/RELEASE-DECISIONS.json" &&
      tracks.keys == %w[sourcePackageRelease runtimeDistribution] &&
      source.fetch("scope") ==
        "PocketRoot source and Swift Package metadata only; no RootFS, " \
        "XCFramework mirror, App, archive, IPA, or binary SDK asset." &&
      runtime.fetch("scope") ==
        "Any App, binary SDK, TestFlight/App Store build, or redistributed " \
        "runtime artifact; excludes every RootFS asset, which remains a " \
        "caller-provided local input." &&
      source.fetch("status") == expected_source_status &&
      runtime.fetch("status") == expected_runtime_status &&
      source_ids == expected_source_ids &&
      runtime_ids == expected_runtime_ids &&
      document.fetch("blockedGateIds") == expected_blocked &&
      document.fetch("nextRequiredDecision") == expected_next_decision &&
      document.fetch("warning") ==
        "Engineering validation is not distribution authorization. A ready " \
        "source track would not authorize runtime, RootFS, App, or binary " \
        "distribution." &&
      valid_gate_shapes
    unless valid_document
      raise ComplianceError,
        "release readiness does not preserve its independent fail-closed gates"
    end
    true
  rescue KeyError, TypeError => error
    raise ComplianceError, "release readiness is incomplete: #{error.message}"
  end

  def checklist_gate_lines(gates, language)
    gates.map do |gate|
      checked = gate.fetch("satisfied") ? "x" : " "
      title =
        language == :zh ? gate.fetch("titleZh") : gate.fetch("title")
      "- [#{checked}] `#{gate.fetch("id")}` — #{title}"
    end.join("\n")
  end

  def release_checklist(readiness_document)
    source_track =
      readiness_document.dig("tracks", "sourcePackageRelease")
    runtime_track =
      readiness_document.dig("tracks", "runtimeDistribution")
    source = source_track.fetch("gates")
    runtime = runtime_track.fetch("gates")
    overall_status =
      readiness_document.fetch("overallStatus") == "ready" ?
        "Ready / 全部轨道已就绪" : "Blocked / 不可发布"
    overall_status_en =
      readiness_document.fetch("overallStatus") == "ready" ?
        "Ready / all tracks releasable" : "Blocked / not releasable"
    source_status =
      source_track.fetch("status") == "ready" ?
        "Ready / 已就绪" : "Blocked / 未就绪"
    runtime_status =
      runtime_track.fetch("status") == "ready" ?
        "Ready / 已就绪" : "Blocked / 未就绪"
    source_status_en =
      source_track.fetch("status") == "ready" ? "Ready" : "Blocked"
    runtime_status_en =
      runtime_track.fetch("status") == "ready" ? "Ready" : "Blocked"
    <<~MARKDOWN
      # PocketRoot v#{RELEASE_VERSION} Release Candidate Checklist

      当前状态：**#{overall_status}**。

      本清单把“源码/Swift Package 发布”和“不包含任何 RootFS 资产的
      runtime、App 或二进制 SDK 分发”分为两条独立轨道。工程测试通过不等于获得
      额外分发授权；源码轨道 Ready 不会自动解除 runtime 轨道。

      ## 源码与 Swift Package 发布（#{source_status}）

      #{checklist_gate_lines(source, :zh)}

      PocketRoot 原创源码的顶层许可证已由项目所有者确定为 MIT；贡献政策与
      `NOTICE.md` 同步生效。源码轨道 Ready 不授权 Runtime、RootFS、App 或二进制
      分发。

      ## Runtime / App / 二进制分发（不含 RootFS，#{runtime_status}）

      #{checklist_gate_lines(runtime, :zh)}

      RootFS 当前只能作为调用方自行取得并授权的本地输入；不得把它加入 Git、
      SwiftPM、GitHub Release、TestFlight 或 App bundle。Runtime 轨道同样要求
      PocketRoot 顶层许可证已确定。当前 `Scripts/scan-release-artifact.rb`
      只生成工程证据；即使扫描签名 `.xcarchive`，也固定保持
      `engineering-evidence-only`、`releaseSignatureValid=false` 和
      `rootFSExcluded=false`。它可以把
      `Compliance/Release/FinalArtifact/v0.1.0/ARTIFACT-INVENTORY.json` 与
      `SBOM.spdx.json` 纳入 composition，但不能解除 runtime 门禁。后续专用最终
      发布验证 schema 必须把签名、entitlement 和风险元数据绑定到被复核的制品，
      并提供内容级 RootFS 排除证明；仅靠内容树摘要、路径、文件名或扩展名不足。

      ## 校验

      ```bash
      ruby Scripts/generate-release-compliance.rb --check
      ruby Scripts/generate-release-compliance.rb --status
      ruby Scripts/generate-release-compliance.rb --require-source-ready
      ruby Scripts/generate-release-compliance.rb --require-runtime-ready
      ```

      两个 `--require-*-ready` 命令分别反映各自轨道；源码轨道当前返回成功，
      Runtime 轨道仍故意返回非零状态。

      ## English

      Current status: **#{overall_status_en}**.

      This checklist separates a source/Swift Package release from runtime,
      App, archive, or binary SDK distribution that excludes every RootFS asset.
      Passing engineering tests is not additional distribution authorization,
      and the Ready source track does not unblock the runtime track.

      ### Source and Swift Package release (#{source_status_en})

      #{checklist_gate_lines(source, :en)}

      The project owner selected MIT for original PocketRoot source. The
      contributor policy and `NOTICE.md` apply with it. A Ready source track
      does not authorize Runtime, RootFS, App, or binary distribution.

      ### Runtime / App / binary distribution (RootFS excluded, #{runtime_status_en})

      #{checklist_gate_lines(runtime, :en)}

      The RootFS remains a caller-obtained and caller-authorized local input. Do
      not add it to Git, SwiftPM, GitHub Releases, TestFlight, or an App bundle.
      The runtime track also requires the finalized PocketRoot top-level
      license. The current `Scripts/scan-release-artifact.rb` schema produces
      engineering evidence only; even a signed `.xcarchive` remains
      `engineering-evidence-only`, with `releaseSignatureValid=false` and
      `rootFSExcluded=false`. Its inventory and SPDX SBOM may be included under
      `Compliance/Release/FinalArtifact/v0.1.0`, but cannot open the runtime
      gate. A future dedicated final-release schema must bind signature,
      entitlement, and risk metadata to the reviewed artifact and provide
      content-based RootFS absence evidence; a content-tree digest, path,
      filename, or extension check is not sufficient.
    MARKDOWN
  end

  def spdx_package(
    id:,
    name:,
    version:,
    download:,
    license_declared:,
    copyright: "NOASSERTION",
    purpose: nil,
    source_info: nil,
    license_comments: nil,
    checksum: nil,
    filename: nil,
    external_refs: []
  )
    package = {
      "SPDXID" => id,
      "name" => name,
      "versionInfo" => version,
      "supplier" => "NOASSERTION",
      "downloadLocation" => download,
      "filesAnalyzed" => false,
      "licenseConcluded" => "NOASSERTION",
      "licenseDeclared" => license_declared,
      "copyrightText" => copyright
    }
    package["primaryPackagePurpose"] = purpose if purpose
    package["sourceInfo"] = source_info if source_info
    package["licenseComments"] = license_comments if license_comments
    package["checksums"] = [
      {"algorithm" => "SHA256", "checksumValue" => checksum}
    ] if checksum
    package["packageFileName"] = filename if filename
    package["externalRefs"] = external_refs unless external_refs.empty?
    package
  end

  def prefixed_rootfs_packages(inputs)
    inputs.fetch(:rootfs_packages).map do |original|
      package = Marshal.load(Marshal.dump(original))
      package["SPDXID"] =
        original.fetch("SPDXID").sub(
          /\ASPDXRef-/,
          "SPDXRef-RootFS-"
        )
      package
    end
  end

  def sbom(composition_document, inputs)
    namespace_digest =
      Digest::SHA256.hexdigest(pretty_json(composition_document))
    ish = ISHEMBED.fetch("ish")
    supervisor = ISHEMBED.fetch("supervisor")
    binary = ISHEMBED.fetch("xcframework")
    corresponding_source = ISHEMBED.fetch("correspondingSource")
    packages = [
      spdx_package(
        id: "SPDXRef-Package-PocketRoot",
        name: "PocketRoot",
        version: RELEASE_VERSION,
        download: "NOASSERTION",
        license_declared: "MIT",
        purpose: "LIBRARY",
        source_info:
          "Original PocketRoot source and Swift Package metadata are " \
          "authorized for source release under MIT. No Runtime, RootFS, App, " \
          "archive, IPA, or binary distribution is asserted.",
        license_comments:
          "The top-level MIT license covers original PocketRoot source only. " \
          "Third-party components retain their respective upstream licenses."
      ),
      spdx_package(
        id: "SPDXRef-Package-IshEmbed",
        name: "IshEmbed",
        version: ISHEMBED.fetch("release"),
        download:
          "https://github.com/jacklv-coder/ish-arm64-pkg/tree/" \
          "#{ISHEMBED.fetch("revision")}",
        license_declared: ISHEMBED.fetch("licenseDeclared"),
        purpose: "LIBRARY",
        source_info:
          "Pinned Git revision #{ISHEMBED.fetch("revision")}.",
        external_refs: [
          {
            "referenceCategory" => "PACKAGE-MANAGER",
            "referenceType" => "purl",
            "referenceLocator" =>
              "pkg:github/jacklv-coder/ish-arm64-pkg@" \
              "#{ISHEMBED.fetch("revision")}"
          }
        ]
      ),
      spdx_package(
        id: "SPDXRef-Package-SwiftTerm",
        name: "SwiftTerm",
        version: SWIFTTERM.fetch("release"),
        download:
          "https://github.com/jacklv-coder/SwiftTerm/tree/" \
          "#{SWIFTTERM.fetch("revision")}",
        license_declared: SWIFTTERM.fetch("licenseDeclared"),
        purpose: "LIBRARY",
        source_info:
          "Pinned Git revision #{SWIFTTERM.fetch("revision")}; the complete " \
          "upstream MIT notice is tracked at #{SWIFTTERM.fetch("noticePath")}.",
        external_refs: [
          {
            "referenceCategory" => "PACKAGE-MANAGER",
            "referenceType" => "purl",
            "referenceLocator" =>
              "pkg:github/jacklv-coder/SwiftTerm@" \
              "#{SWIFTTERM.fetch("revision")}"
          }
        ]
      ),
      spdx_package(
        id: "SPDXRef-Package-Swift-Argument-Parser",
        name: "swift-argument-parser",
        version: SWIFT_ARGUMENT_PARSER.fetch("release"),
        download:
          "https://github.com/apple/swift-argument-parser/tree/" \
          "#{SWIFT_ARGUMENT_PARSER.fetch("revision")}",
        license_declared: SWIFT_ARGUMENT_PARSER.fetch("licenseDeclared"),
        purpose: "LIBRARY",
        source_info:
          "Resolved through the pinned SwiftTerm package manifest. The selected " \
          "SwiftTerm library product does not link the Termcast executable or " \
          "ArgumentParser product.",
        external_refs: [
          {
            "referenceCategory" => "PACKAGE-MANAGER",
            "referenceType" => "purl",
            "referenceLocator" =>
              "pkg:github/apple/swift-argument-parser@" \
              "#{SWIFT_ARGUMENT_PARSER.fetch("revision")}"
          }
        ]
      ),
      spdx_package(
        id: "SPDXRef-Package-IshKernel-XCFramework",
        name: "libIshKernel.xcframework",
        version: ISHEMBED.fetch("assetRelease"),
        download: binary.fetch("url"),
        license_declared: "NOASSERTION",
        purpose: "FRAMEWORK",
        source_info:
          "Prebuilt arm64 iOS device and Simulator binary generated from " \
          "the paired IshEmbed corresponding-source asset.",
        license_comments:
          "The archive aggregates IshEmbed, the pinned iSH fork, and a " \
          "statically linked musl supervisor; final legal conclusions remain open.",
        checksum: binary.fetch("sha256"),
        filename: binary.fetch("filename")
      ),
      spdx_package(
        id: "SPDXRef-Package-IshEmbed-Corresponding-Source",
        name: "IshEmbed corresponding source",
        version: ISHEMBED.fetch("assetRelease"),
        download: corresponding_source.fetch("url"),
        license_declared: "NOASSERTION",
        purpose: "SOURCE",
        source_info:
          "Contains the pinned IshEmbed and iSH sources plus the exact musl " \
          "source snapshot used by the guest supervisor.",
        checksum: corresponding_source.fetch("sha256"),
        filename: corresponding_source.fetch("filename")
      ),
      spdx_package(
        id: "SPDXRef-Package-iSH",
        name: "iSH PocketRoot fork",
        version: ish.fetch("revision"),
        download:
          "https://github.com/jacklv-coder/ish-arm64/tree/" \
          "#{ish.fetch("revision")}",
        license_declared: ish.fetch("licenseDeclared"),
        purpose: "LIBRARY",
        source_info:
          "Expanded from IshEmbed gitlink #{ish.fetch("path")} at " \
          "#{ish.fetch("revision")}.",
        license_comments:
          "The pinned source also carries LICENSE.IOS terms for Apple App " \
          "Store distribution; legal review remains open.",
        external_refs: [
          {
            "referenceCategory" => "PACKAGE-MANAGER",
            "referenceType" => "purl",
            "referenceLocator" =>
              "pkg:github/jacklv-coder/ish-arm64@#{ish.fetch("revision")}"
          }
        ]
      ),
      spdx_package(
        id: "SPDXRef-Package-musl-supervisor-source",
        name: "musl source snapshot for IshEmbed guest supervisor",
        version: "Zig-0.16.0-snapshot",
        download: "NOASSERTION",
        license_declared: supervisor.fetch("muslLicenseDeclared"),
        copyright: "Copyright 2005-2020 Rich Felker, et al.",
        purpose: "SOURCE",
        source_info:
          "Normalized source-tree SHA-256 " \
          "#{supervisor.fetch("muslSourceSha256")} from " \
          "#{supervisor.fetch("toolchain")} targeting " \
          "#{supervisor.fetch("target")}."
      ),
      spdx_package(
        id: "SPDXRef-Package-External-RootFS",
        name: "PocketRoot external Alpine RootFS",
        version: ROOTFS.fetch("version"),
        download: ROOTFS.fetch("url"),
        license_declared: "NOASSERTION",
        purpose: "OPERATING_SYSTEM",
        source_info:
          "Caller-provided local input; never bundled or downloaded by the " \
          "PocketRoot library. Contains Alpine " \
          "#{ROOTFS.fetch("guestVersion")} #{ROOTFS.fetch("architecture")}.",
        license_comments:
          "The RootFS license/NOTICE, corresponding-source delivery, legal, " \
          "and redistribution gates remain open.",
        checksum: ROOTFS.fetch("sha256"),
        filename: ROOTFS.fetch("filename")
      )
    ] + prefixed_rootfs_packages(inputs)

    relationships = [
      {
        "spdxElementId" => "SPDXRef-DOCUMENT",
        "relationshipType" => "DESCRIBES",
        "relatedSpdxElement" => "SPDXRef-Package-PocketRoot"
      },
      {
        "spdxElementId" => "SPDXRef-Package-PocketRoot",
        "relationshipType" => "DEPENDS_ON",
        "relatedSpdxElement" => "SPDXRef-Package-IshEmbed",
        "comment" =>
          "Only the opt-in PocketRootIshRuntime product uses this dependency."
      },
      {
        "spdxElementId" => "SPDXRef-Package-PocketRoot",
        "relationshipType" => "DEPENDS_ON",
        "relatedSpdxElement" => "SPDXRef-Package-SwiftTerm",
        "comment" =>
          "Only PocketRootTerminal on iOS selects the SwiftTerm library product."
      },
      {
        "spdxElementId" => "SPDXRef-Package-SwiftTerm",
        "relationshipType" => "DEPENDS_ON",
        "relatedSpdxElement" =>
          "SPDXRef-Package-Swift-Argument-Parser",
        "comment" =>
          "The package resolver records this manifest dependency, but the " \
          "selected SwiftTerm library target does not link ArgumentParser."
      },
      {
        "spdxElementId" => "SPDXRef-Package-IshEmbed",
        "relationshipType" => "DEPENDS_ON",
        "relatedSpdxElement" => "SPDXRef-Package-IshKernel-XCFramework"
      },
      {
        "spdxElementId" => "SPDXRef-Package-IshKernel-XCFramework",
        "relationshipType" => "GENERATED_FROM",
        "relatedSpdxElement" =>
          "SPDXRef-Package-IshEmbed-Corresponding-Source"
      },
      {
        "spdxElementId" => "SPDXRef-Package-IshKernel-XCFramework",
        "relationshipType" => "GENERATED_FROM",
        "relatedSpdxElement" => "SPDXRef-Package-iSH"
      },
      {
        "spdxElementId" => "SPDXRef-Package-IshKernel-XCFramework",
        "relationshipType" => "STATIC_LINK",
        "relatedSpdxElement" =>
          "SPDXRef-Package-musl-supervisor-source"
      },
      {
        "spdxElementId" => "SPDXRef-Package-PocketRoot",
        "relationshipType" => "DEPENDS_ON",
        "relatedSpdxElement" => "SPDXRef-Package-External-RootFS",
        "comment" =>
          "Only a caller-selected native runtime profile requires the " \
          "external local RootFS input."
      }
    ]
    prefixed_rootfs_packages(inputs).each do |package|
      relationships << {
        "spdxElementId" => "SPDXRef-Package-External-RootFS",
        "relationshipType" => "CONTAINS",
        "relatedSpdxElement" => package.fetch("SPDXID")
      }
    end

    {
      "spdxVersion" => "SPDX-2.3",
      "dataLicense" => "CC0-1.0",
      "SPDXID" => "SPDXRef-DOCUMENT",
      "name" =>
        "PocketRoot experimental full-graph composition #{RELEASE_VERSION}",
      "documentNamespace" =>
        "https://github.com/jacklv-coder/PocketRoot/sbom/release/" \
        "experimental-v#{RELEASE_VERSION}/#{namespace_digest}",
      "creationInfo" => {
        "created" => GENERATED_AT,
        "creators" => [
          "Tool: PocketRoot Scripts/generate-release-compliance.rb"
        ]
      },
      "documentDescribes" => ["SPDXRef-Package-PocketRoot"],
      "packages" => packages,
      "relationships" => relationships
    }
  end

  def readme(final_artifact_evidence)
    final_artifact_status_zh =
      if final_artifact_evidence.fetch("status") == "not-provided"
        <<~TEXT.chomp
          PocketRoot 原创源码已依据 MIT 获准发布；Runtime 的完整 LICENSE/NOTICE、
          对应源码交付、App Store 2.5.2、法律审查和发行授权仍未完成。由于没有最终
          archive，本目录明确保持
          `completeReleaseArtifactSBOM=false`、`distributionAuthorized=false`。
          `finalArtifactEvidence.status=not-provided` 还会阻止 Runtime 轨道在没有精确
          制品清单、SBOM 和人工复核 SHA-256 的情况下变为 Ready。
        TEXT
      else
        <<~TEXT.chomp
          PocketRoot 原创源码已依据 MIT 获准发布；Runtime 的完整 LICENSE/NOTICE、
          对应源码交付、App Store 2.5.2、法律审查和发行授权仍未完成。当前已纳入
          最终制品目录中的工程扫描证据，但状态保持
          `engineering-evidence-only`、`releaseSignatureValid=false`、
          `rootFSExcluded=false`；这份证据不能解除 Runtime 发布门禁。
        TEXT
      end
    final_artifact_status_en =
      if final_artifact_evidence.fetch("status") == "not-provided"
        <<~TEXT.chomp
          original PocketRoot source is authorized for release under MIT. The Runtime's
          complete LICENSE/NOTICE set, corresponding-source delivery, App Store 2.5.2
          disposition, legal review, and distribution authorization remain open.
          Because no final archive was scanned, this evidence keeps
          `completeReleaseArtifactSBOM=false` and `distributionAuthorized=false`.
          `finalArtifactEvidence.status=not-provided` also prevents the runtime
          track from becoming Ready without an exact artifact inventory, SPDX SBOM,
          and code-reviewed artifact SHA-256.
        TEXT
      else
        <<~TEXT.chomp
          current final-artifact directory contains engineering scan evidence,
          while original PocketRoot source is authorized for release under MIT.
          The Runtime's complete LICENSE/NOTICE set, corresponding-source delivery,
          App Store 2.5.2 disposition, legal review, and distribution authorization
          remain open. The imported evidence remains `engineering-evidence-only`, with
          `releaseSignatureValid=false` and `rootFSExcluded=false`; it cannot open
          the runtime release gate.
        TEXT
      end
    <<~MARKDOWN
      # PocketRoot experimental release-composition evidence

      此目录记录 `#{RELEASE_VERSION}` 源码树可复现的**最大实验组合**，不是已构建、
      已扫描或获准发行的 App 制品。`COMPOSITION.json` 区分默认 Demo、独立宿主示例、
      原生 runtime smoke 与全部 Swift products；`SBOM.spdx.json` 汇总 PocketRoot、固定 ABI.9
      IshEmbed/XCFramework、精确 iSH gitlink、静态 supervisor 使用的 musl source、
      固定 SwiftTerm 与其解析依赖，以及调用方提供的外部 RootFS 和其中 15 个 Alpine 包。
      `READINESS.json` 和 `RELEASE-CHECKLIST.md` 把源码/Swift Package 发布与
      不含 RootFS 资产的 runtime/App/二进制分发拆成两个独立、默认关闭的轨道。

      默认 Demo 显式链接 IshEmbed，但仓库不包含 RootFS；只有本地 Debug 构建可把
      精确固定的仓库外资产注入 App，Release 明确跳过。RootFS 不由库下载。
      #{final_artifact_status_zh}

      校验：

      ```bash
      ruby Scripts/generate-release-compliance.rb --check
      ruby Scripts/generate-release-compliance.rb --status
      ```

      ## English

      This directory records the reproducible **maximal experimental
      composition** of the `#{RELEASE_VERSION}` source tree. It is not a built,
      scanned, or authorized App artifact. `COMPOSITION.json` distinguishes the
      default Demo, standalone host example, native-runtime smoke, and all
      Swift products.
      `SBOM.spdx.json` combines PocketRoot, pinned ABI.9 IshEmbed/XCFramework,
      the exact iSH gitlink, the musl source snapshot used by the static guest
      supervisor, pinned SwiftTerm and its resolved dependency, and the
      caller-provided external RootFS with its 15 Alpine packages.
      `READINESS.json` and `RELEASE-CHECKLIST.md` split source/Swift Package
      release from runtime/App/binary distribution that excludes every RootFS
      asset into two independent, fail-closed tracks.

      The default Demo explicitly links IshEmbed, but the repository contains
      no RootFS. Only a local Debug build may inject the exact pinned external
      asset; Release skips it. The library never downloads the RootFS. The
      #{final_artifact_status_en}
    MARKDOWN
  end

  def validate_final_artifact_evidence(summary, repository_evidence)
    expected_keys = %w[
      status
      evidenceDirectory
      inventoryPath
      inventorySha256
      sbomPath
      sbomSha256
      artifactSha256
      inputKind
      releaseSignatureValid
      rootFSExcluded
      rootFSAssetPaths
    ]
    unless summary.keys == expected_keys &&
      summary.fetch("evidenceDirectory") ==
        FINAL_ARTIFACT_EVIDENCE_RELATIVE &&
      summary.fetch("inventoryPath") ==
        FINAL_ARTIFACT_INVENTORY_RELATIVE &&
      summary.fetch("sbomPath") == FINAL_ARTIFACT_SBOM_RELATIVE &&
      (
        summary.fetch("rootFSExcluded").instance_of?(TrueClass) ||
          summary.fetch("rootFSExcluded").instance_of?(FalseClass)
      ) &&
      (
        summary.fetch("releaseSignatureValid").instance_of?(TrueClass) ||
          summary.fetch("releaseSignatureValid").instance_of?(FalseClass)
      )
      raise ComplianceError,
        "final artifact evidence summary shape drifted"
    end
    paths = summary.fetch("rootFSAssetPaths")
    unless paths.is_a?(Array) &&
      paths.all? { |path| path.is_a?(String) && !path.empty? } &&
      paths == paths.uniq.sort
      raise ComplianceError,
        "final artifact RootFS asset path evidence drifted"
    end
    if summary.fetch("status") == "not-provided"
      valid_absent =
        %w[
          inventorySha256
          sbomSha256
          artifactSha256
        ].all? { |key| summary.fetch(key).nil? } &&
          summary.fetch("inputKind").nil? &&
          summary.fetch("releaseSignatureValid") == false &&
          summary.fetch("rootFSExcluded") == false &&
          paths.empty? &&
          !repository_evidence.key?(FINAL_ARTIFACT_INVENTORY_RELATIVE) &&
          !repository_evidence.key?(FINAL_ARTIFACT_SBOM_RELATIVE)
      unless valid_absent
        raise ComplianceError,
          "absent final artifact evidence is not fail-closed"
      end
    elsif summary.fetch("status") == "engineering-evidence-only"
      valid_hashes =
        %w[
          inventorySha256
          sbomSha256
          artifactSha256
        ].all? do |key|
          value = summary.fetch(key)
          value.is_a?(String) && value.match?(HASH_PATTERN)
        end
      valid_repository_binding =
        repository_evidence[FINAL_ARTIFACT_INVENTORY_RELATIVE] ==
          summary.fetch("inventorySha256") &&
          repository_evidence[FINAL_ARTIFACT_SBOM_RELATIVE] ==
            summary.fetch("sbomSha256")
      unless valid_hashes &&
        valid_repository_binding &&
        %w[app xcarchive].include?(summary.fetch("inputKind")) &&
        summary.fetch("releaseSignatureValid") == false &&
        summary.fetch("rootFSExcluded") == false
        raise ComplianceError,
          "present final artifact evidence is not fail-closed and " \
          "content-addressed"
      end
    else
      raise ComplianceError,
        "final artifact evidence has an unsupported status"
    end
    true
  rescue KeyError, TypeError => error
    raise ComplianceError,
      "final artifact evidence is incomplete: #{error.message}"
  end

  def validate_composition(document)
    coverage = document.fetch("coverage")
    true_gates = %w[
      swiftProductInventoryComplete
      applicationTargetInventoryComplete
      externalDependencyPinsComplete
      rootFSPackageSBOMEmbedded
      releaseCompositionSBOMGenerated
      topLevelLicenseFinalized
    ]
    false_gates = %w[
      releaseArtifactBuilt
      releaseArtifactScanned
      binaryFilesAnalyzed
      completeReleaseArtifactSBOM
      completeLicenseAndNoticeBundle
      correspondingSourceDeliveryApproved
      appStorePolicyApproved
      legalReviewApproved
      distributionAuthorized
    ]
    unless document.fetch("schemaVersion") == 1 &&
      document.fetch("generatedAt") == GENERATED_AT &&
      document.dig("release", "version") == RELEASE_VERSION &&
      document.dig("release", "status") ==
        "experimental-engineering-composition-not-distribution-candidate" &&
      true_gates.all? { |gate| coverage[gate] == true } &&
      false_gates.all? { |gate| coverage[gate] == false } &&
      coverage.keys.sort == (true_gates + false_gates).sort
      raise ComplianceError,
        "release composition does not preserve its exact coverage gates"
    end
    profiles = document.fetch("profiles")
    validate_final_artifact_evidence(
      document.fetch("finalArtifactEvidence"),
      document.fetch("repositoryEvidence")
    )
    unless profiles.map { |profile| profile.fetch("id") } == %w[
      default-demo
      native-runtime-smoke
      standalone-host-example
      two-entry-quick-start-example
      external-consumer-acceptance
      swift-package-all-products
    ] &&
      profiles.all? { |profile| profile["artifactBuiltAndScanned"] == false } &&
      document.dig(
        "externalComponents",
        "rootFS",
        "bundledByDefault"
      ) == false &&
      document.dig(
        "externalComponents",
        "rootFS",
        "downloadedByLibrary"
      ) == false
      raise ComplianceError, "release composition profiles drifted"
    end
    true
  rescue KeyError, TypeError => error
    raise ComplianceError, "release composition is incomplete: #{error.message}"
  end

  def validate_sbom(document, composition_document)
    packages = document.fetch("packages")
    relationships = document.fetch("relationships")
    ids = packages.map { |package| package.fetch("SPDXID") }
    valid_ids = ids + ["SPDXRef-DOCUMENT"]
    expected_namespace_digest =
      Digest::SHA256.hexdigest(pretty_json(composition_document))
    unless document.fetch("spdxVersion") == "SPDX-2.3" &&
      document.fetch("dataLicense") == "CC0-1.0" &&
      document.fetch("SPDXID") == "SPDXRef-DOCUMENT" &&
      document.fetch("documentDescribes") ==
        ["SPDXRef-Package-PocketRoot"] &&
      document.fetch("documentNamespace").end_with?(
        "/#{expected_namespace_digest}"
      ) &&
      packages.length == 24 &&
      ids.uniq.length == ids.length &&
      ids.all? { |id| id.match?(/\ASPDXRef-[A-Za-z0-9.-]+\z/) }
      raise ComplianceError, "release SPDX document or package set drifted"
    end
    packages.each do |package|
      purpose = package["primaryPackagePurpose"]
      unless package.fetch("filesAnalyzed") == false &&
        package.fetch("licenseConcluded") == "NOASSERTION" &&
        package.fetch("licenseDeclared").is_a?(String) &&
        !package.fetch("licenseDeclared").empty? &&
        (purpose.nil? || SPDX_PACKAGE_PURPOSES.include?(purpose))
        raise ComplianceError, "release SPDX package analysis state drifted"
      end
      package.fetch("checksums", []).each do |checksum|
        unless checksum == {
          "algorithm" => "SHA256",
          "checksumValue" => checksum.fetch("checksumValue")
        } &&
          checksum.fetch("checksumValue").match?(HASH_PATTERN)
          raise ComplianceError, "release SPDX package checksum is invalid"
        end
      end
    end
    relationships.each do |relationship|
      unless valid_ids.include?(relationship.fetch("spdxElementId")) &&
        valid_ids.include?(relationship.fetch("relatedSpdxElement"))
        raise ComplianceError, "release SPDX relationship has a dangling ID"
      end
    end
    rootfs_contains = relationships.select do |relationship|
      relationship["spdxElementId"] ==
        "SPDXRef-Package-External-RootFS" &&
        relationship["relationshipType"] == "CONTAINS"
    end
    unless rootfs_contains.length == 15 &&
      relationships.count do |relationship|
        relationship["relationshipType"] == "DESCRIBES"
      end == 1
      raise ComplianceError, "release SPDX relationship coverage drifted"
    end
    true
  rescue KeyError, TypeError => error
    raise ComplianceError, "release SPDX SBOM is incomplete: #{error.message}"
  end

  def build_outputs(root = repository_root)
    inputs = collect_inputs(root)
    composition_document = composition(inputs)
    validate_composition(composition_document)
    readiness_document = readiness(composition_document, inputs)
    validate_readiness(readiness_document)
    sbom_document = sbom(composition_document, inputs)
    validate_sbom(sbom_document, composition_document)
    outputs = {
      "COMPOSITION.json" => pretty_json(composition_document),
      "READINESS.json" => pretty_json(readiness_document),
      "README.md" =>
        readme(composition_document.fetch("finalArtifactEvidence")),
      "RELEASE-CHECKLIST.md" => release_checklist(readiness_document),
      "SBOM.spdx.json" => pretty_json(sbom_document)
    }
    checksum_lines = outputs.sort.map do |filename, contents|
      "#{Digest::SHA256.hexdigest(contents)}  #{filename}"
    end
    outputs["SHA256SUMS"] = "#{checksum_lines.join("\n")}\n"
    outputs
  end

  def check(directory = output_directory, root = repository_root)
    outputs = build_outputs(root)
    unless directory.directory? && !directory.symlink?
      raise ComplianceError,
        "release compliance directory is missing: #{directory}"
    end
    actual = directory.children.map(&:basename).map(&:to_s).sort
    unless actual == OUTPUT_FILENAMES.sort
      raise ComplianceError,
        "release compliance file set drifted: #{actual.inspect}"
    end
    outputs.each do |filename, contents|
      path = directory.join(filename)
      unless !path.symlink? && path.file? && path.binread == contents.b
        raise ComplianceError,
          "release compliance output is stale: #{path}"
      end
    end
    true
  end

  def materialize(path, root = repository_root)
    output = Pathname(path)
    raise ComplianceError, "--output must be absolute" unless output.absolute?
    if output.exist? || output.symlink?
      raise ComplianceError, "--output already exists: #{output}"
    end
    unless output.parent.directory? && !output.parent.symlink?
      raise ComplianceError, "--output parent must be a real directory"
    end
    resolved_parent = output.parent.realpath
    resolved_output = resolved_parent.join(output.basename)
    if resolved_output.exist? || resolved_output.symlink?
      raise ComplianceError, "--output already exists: #{resolved_output}"
    end
    if resolved_output.to_s.start_with?(
      "#{repository_root}#{File::SEPARATOR}"
    )
      raise ComplianceError, "--output must be outside the repository"
    end
    staging =
      resolved_parent.join(
        ".#{output.basename}.staging-#{SecureRandom.hex(8)}"
      )
    raise ComplianceError, "staging path already exists: #{staging}" if staging.exist?

    begin
      staging.mkdir(0o700)
      build_outputs(root).each do |filename, contents|
        destination = staging.join(filename)
        destination.binwrite(contents)
        destination.chmod(0o600)
      end
      File.rename(staging, resolved_output)
    ensure
      FileUtils.remove_entry(staging) if staging.exist?
    end
    resolved_output
  end

  def parse_options(arguments)
    options = {
      check: false,
      validate_only: false,
      status: false,
      require_source_ready: false,
      require_runtime_ready: false
    }
    parser = OptionParser.new do |commands|
      commands.banner =
        "Usage: ruby Scripts/generate-release-compliance.rb [options]"
      commands.on("--check", "Check committed release-composition evidence") do
        options[:check] = true
      end
      commands.on("--validate-only", "Validate inputs without writing") do
        options[:validate_only] = true
      end
      commands.on("--status", "Print fail-closed release readiness") do
        options[:status] = true
      end
      commands.on(
        "--require-source-ready",
        "Fail unless the source/Swift Package release track is ready"
      ) do
        options[:require_source_ready] = true
      end
      commands.on(
        "--require-runtime-ready",
        "Fail unless the runtime distribution track is ready"
      ) do
        options[:require_runtime_ready] = true
      end
      commands.on("--output DIR", "Create a new external evidence directory") do |value|
        options[:output] = value
      end
    end
    parser.parse!(arguments)
    raise OptionParser::InvalidOption, arguments.join(" ") unless arguments.empty?
    modes = [
      options.fetch(:check),
      options.fetch(:validate_only),
      options.fetch(:status),
      options.fetch(:require_source_ready),
      options.fetch(:require_runtime_ready),
      !options[:output].nil?
    ].count(true)
    unless modes == 1
      raise OptionParser::InvalidOption,
        "select exactly one mode: --check, --validate-only, --status, " \
        "--require-source-ready, --require-runtime-ready, or --output"
    end
    options
  end

  def release_readiness(root = repository_root)
    JSON.parse(build_outputs(root).fetch("READINESS.json"))
  end

  def print_readiness_status(document)
    puts "PocketRoot v#{document.fetch("releaseVersion")} release readiness: " \
      "#{document.fetch("overallStatus").upcase}"
    document.fetch("tracks").each do |name, track|
      blocked =
        track.fetch("gates").reject { |gate| gate.fetch("satisfied") }
      puts "- #{name}: #{track.fetch("status").upcase}"
      blocked.each do |gate|
        puts "  - #{gate.fetch("id")}: #{gate.fetch("requiredAction")}"
      end
    end
    puts document.fetch("warning")
  end

  def require_ready_track(document, track_name)
    track = document.fetch("tracks").fetch(track_name)
    return true if track.fetch("status") == "ready"

    blocked =
      track.fetch("gates").reject { |gate| gate.fetch("satisfied") }
    warn "#{track_name} is BLOCKED:"
    blocked.each do |gate|
      warn "- #{gate.fetch("id")}: #{gate.fetch("requiredAction")}"
    end
    false
  end

  def execute(arguments)
    options = parse_options(arguments)
    if options.fetch(:check)
      check
      puts "Release composition, readiness, and SPDX SBOM are reproducible."
    elsif options.fetch(:validate_only)
      outputs = build_outputs
      sbom_document = JSON.parse(outputs.fetch("SBOM.spdx.json"))
      puts "Release composition inputs are valid " \
        "(#{sbom_document.fetch("packages").length} SPDX packages)."
    elsif options.fetch(:status)
      print_readiness_status(release_readiness)
    elsif options.fetch(:require_source_ready)
      readiness_document = release_readiness
      return 2 unless require_ready_track(
        readiness_document,
        "sourcePackageRelease"
      )
      puts "Source and Swift Package release track is READY."
    elsif options.fetch(:require_runtime_ready)
      readiness_document = release_readiness
      return 2 unless require_ready_track(
        readiness_document,
        "runtimeDistribution"
      )
      puts "Runtime distribution track is READY."
    else
      output = materialize(options.fetch(:output))
      puts "Materialized release-composition evidence at #{output}."
    end
    0
  rescue ComplianceError, OptionParser::ParseError, SystemCallError => error
    warn error.message
    1
  end
end

if $PROGRAM_NAME == __FILE__
  exit PocketRootReleaseCompliance.execute(ARGV)
end
