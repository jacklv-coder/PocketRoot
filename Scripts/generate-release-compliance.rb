#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "securerandom"
require "yaml"
require_relative "pocketroot-deterministic-json"

module PocketRootReleaseCompliance
  RELEASE_VERSION = "0.1.0"
  GENERATED_AT = "2026-07-28T00:00:00Z"
  OUTPUT_RELATIVE = "Compliance/Release/experimental-v0.1.0"
  ISHEMBED = {
    "repository" => "https://github.com/jacklv-coder/ish-arm64-pkg.git",
    "revision" => "38d25d6f8726145e7e988172f12000020d89a638",
    "release" => "v0.4.0-abi.6",
    "licenseDeclared" => "GPL-3.0-or-later",
    "xcframework" => {
      "filename" => "libIshKernel.xcframework.zip",
      "url" =>
        "https://github.com/jacklv-coder/ish-arm64-pkg/releases/download/" \
        "v0.4.0-abi.6/libIshKernel.xcframework.zip",
      "byteCount" => 2_450_755,
      "sha256" =>
        "049422af47334a323dbe26fa7eb431160ef0742495783bd50d1c3949dd0c6720"
    },
    "correspondingSource" => {
      "filename" => "IshEmbed-corresponding-source.tar.gz",
      "url" =>
        "https://github.com/jacklv-coder/ish-arm64-pkg/releases/download/" \
        "v0.4.0-abi.6/IshEmbed-corresponding-source.tar.gz",
      "byteCount" => 2_364_382,
      "sha256" =>
        "a94dbfa58289270ec83aefc5ed1632198290956fd5d1ca381e90dd2ec7f518fa"
    },
    "ish" => {
      "repository" => "https://github.com/jacklv-coder/ish-arm64.git",
      "path" => "third_party/ish",
      "revision" => "c36dfd25462737b45559eb48d4b09f799471572e",
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
    "repository" => "https://github.com/migueldeicaza/SwiftTerm.git",
    "revision" => "dd2fb8ac5b861e7bf617c872895e338f38165648",
    "release" => "v1.15.0",
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
        "target:PocketRootIshRuntime"
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
    "Demo/PocketRootDemo/Resources/Assets.xcassets/Contents.json" =>
      "0fd49ba3c3585c709678e0046a821c3c60685ec7063720d30d3a3448be3a208b",
    "Sources/PocketRootResources/Resources/.gitkeep" =>
      "01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b",
    "Sources/PocketRootResources/Resources/README.txt" =>
      "41df51e7edc0774f807c1cb7e423e2cd04f2a1029ac2d6bbcd097f9bb679a5ea"
  }.freeze
  EXPECTED_REPOSITORY_FILES = {
    "LICENSE" =>
      "9858dd8b44db130c423cb772ec04d1a16fceb4fa57c679b27e301b9f76861bba",
    "Package.resolved" =>
      "0af53a967822dfe3ad3aca7c5c319c5d0922c3f0ab57bbda19a92baac0aa273a",
    "Package.swift" =>
      "fff762dc74981f136159838d480f1d28deb292100e74ebdcd2589885366c3a4f",
    "project.yml" =>
      "dde326aa375b5c63362e3696402e52e023c9d1f88a26c751a652d42fa24a2800",
    "Examples/PocketRootHostApp/project.yml" =>
      "6895e39bd2233525013e3cf087ddfb1f15788bb57dd689b979bf340c1b6ab83e",
    "Scripts/inject-demo-rootfs.sh" =>
      "3982b5382b0d1e13e0c8e8a5bb5404c5bad1dfc4d6e9cd23a39e3395a83087bb",
    "Scripts/run-host-app-ui-smoke.sh" =>
      "e25eb244ca6295ec93bd3c43bc7c48efc49d1a68100bb674d0396928b925f6a6",
    "ThirdPartyNotices/SwiftTerm-LICENSE.txt" =>
      "1c34c11581e20feb2b7ea122146a6690261dae94b2c8444e8cff902e567df6ae"
  }.freeze
  IMPLEMENTATION_ROOTS = %w[
    Sources
    Demo/PocketRootDemo
    Examples/PocketRootHostApp/Sources
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
    README.md
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
    Pathname(__dir__).parent.realpath
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
            /revision:\s*"#{Regexp.escape(expected.fetch("revision"))}"\s*\z/m
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
        "state" => {"revision" => ISHEMBED.fetch("revision")}
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
        "state" => {"revision" => SWIFTTERM.fetch("revision")}
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
      project["packages"] == {"PocketRoot" => {"path" => "."}}
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
          {"path" => "Spikes/PocketRootIshRuntimeCompileSpike"}
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
          {"path" => "Spikes/PocketRootIshRuntimeSmoke"}
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
            "path" => "Demo/PocketRootDemo",
            "excludes" => ["Resources"]
          }
        ],
        "resources" => [
          {"path" => "Demo/PocketRootDemo/Resources"}
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
            "script" => "\"$SRCROOT/Scripts/inject-demo-rootfs.sh\"\n",
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
          {"path" => "Tests/PocketRootDemoTests", "optional" => true}
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
      root.join("Demo/PocketRootDemo/Resources"),
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

  def collect_inputs(root = repository_root)
    package_swift =
      read_regular(root.join("Package.swift"), "Package.swift")
    package_resolved, package_resolved_bytes =
      load_json(root.join("Package.resolved"), "Package.resolved")
    project_bytes = read_regular(root.join("project.yml"), "project.yml")
    host_project_bytes =
      read_regular(
        root.join("Examples/PocketRootHostApp/project.yml"),
        "Host App project.yml"
      )
    license_bytes = read_regular(root.join("LICENSE"), "LICENSE")
    demo_rootfs_injection_bytes =
      read_regular(
        root.join("Scripts/inject-demo-rootfs.sh"),
        "Demo RootFS injection script"
      )
    host_app_ui_smoke_bytes =
      read_regular(
        root.join("Scripts/run-host-app-ui-smoke.sh"),
        "Host App UI smoke script"
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

    unless license_bytes.include?("license has not yet been finalized") &&
      license_bytes.include?("no permission is granted")
      raise ComplianceError,
        "PocketRoot LICENSE no longer matches the unfinalized-license gate"
    end

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
      "Package.resolved" => Digest::SHA256.hexdigest(package_resolved_bytes),
      "Package.swift" => Digest::SHA256.hexdigest(package_swift),
      "project.yml" => Digest::SHA256.hexdigest(project_bytes),
      "Examples/PocketRootHostApp/project.yml" =>
        Digest::SHA256.hexdigest(host_project_bytes),
      "Scripts/inject-demo-rootfs.sh" =>
        Digest::SHA256.hexdigest(demo_rootfs_injection_bytes),
      "Scripts/run-host-app-ui-smoke.sh" =>
        Digest::SHA256.hexdigest(host_app_ui_smoke_bytes),
      SWIFTTERM.fetch("noticePath") =>
        Digest::SHA256.hexdigest(swiftterm_notice_bytes)
    }
    unless file_sha256 == EXPECTED_REPOSITORY_FILES
      raise ComplianceError,
        "versioned release-composition repository input digest drifted"
    end
    file_sha256.merge!(implementation_files)
    file_sha256.merge!(resource_files)
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
        "topLevelLicenseFinalized" => false,
        "completeLicenseAndNoticeBundle" => false,
        "correspondingSourceDeliveryApproved" => false,
        "appStorePolicyApproved" => false,
        "legalReviewApproved" => false,
        "distributionAuthorized" => false
      }
    }
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
        license_declared: "NOASSERTION",
        purpose: "LIBRARY",
        source_info:
          "Current repository source composition; no release commit or " \
          "distribution artifact is asserted.",
        license_comments:
          "The checked-in PocketRoot licensing notice states that the " \
          "top-level license is not finalized and grants no permission."
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
          "https://github.com/migueldeicaza/SwiftTerm/tree/" \
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
              "pkg:github/migueldeicaza/SwiftTerm@" \
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
        version: ISHEMBED.fetch("release"),
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
        version: ISHEMBED.fetch("release"),
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

  def readme
    <<~MARKDOWN
      # PocketRoot experimental release-composition evidence

      此目录记录 `#{RELEASE_VERSION}` 源码树可复现的**最大实验组合**，不是已构建、
      已扫描或获准发行的 App 制品。`COMPOSITION.json` 区分默认 Demo、独立宿主示例、
      原生 runtime smoke 与全部 Swift products；`SBOM.spdx.json` 汇总 PocketRoot、固定 ABI.6
      IshEmbed/XCFramework、精确 iSH gitlink、静态 supervisor 使用的 musl source、
      固定 SwiftTerm 与其解析依赖，以及调用方提供的外部 RootFS 和其中 15 个 Alpine 包。

      默认 Demo 显式链接 IshEmbed，但仓库不包含 RootFS；只有本地 Debug 构建可把
      精确固定的仓库外资产注入 App，Release 明确跳过。RootFS 不由库下载。
      顶层许可证、完整 LICENSE/NOTICE、对应源码交付、App Store 2.5.2、法律审查和
      发行授权仍未完成。由于没有最终 archive，本目录明确保持
      `completeReleaseArtifactSBOM=false`、`distributionAuthorized=false`。

      校验：

      ```bash
      ruby Scripts/generate-release-compliance.rb --check
      ```

      ## English

      This directory records the reproducible **maximal experimental
      composition** of the `#{RELEASE_VERSION}` source tree. It is not a built,
      scanned, or authorized App artifact. `COMPOSITION.json` distinguishes the
      default Demo, standalone host example, native-runtime smoke, and all
      Swift products.
      `SBOM.spdx.json` combines PocketRoot, pinned ABI.6 IshEmbed/XCFramework,
      the exact iSH gitlink, the musl source snapshot used by the static guest
      supervisor, pinned SwiftTerm and its resolved dependency, and the
      caller-provided external RootFS with its 15 Alpine packages.

      The default Demo explicitly links IshEmbed, but the repository contains
      no RootFS. Only a local Debug build may inject the exact pinned external
      asset; Release skips it. The library never downloads the RootFS. The
      top-level license, complete LICENSE/NOTICE set, corresponding-source delivery,
      App Store 2.5.2 disposition, legal review, and distribution authorization
      remain open. Because no final archive was scanned, this evidence keeps
      `completeReleaseArtifactSBOM=false` and `distributionAuthorized=false`.
    MARKDOWN
  end

  def validate_composition(document)
    coverage = document.fetch("coverage")
    true_gates = %w[
      swiftProductInventoryComplete
      applicationTargetInventoryComplete
      externalDependencyPinsComplete
      rootFSPackageSBOMEmbedded
      releaseCompositionSBOMGenerated
    ]
    false_gates = %w[
      releaseArtifactBuilt
      releaseArtifactScanned
      binaryFilesAnalyzed
      completeReleaseArtifactSBOM
      topLevelLicenseFinalized
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
    unless profiles.map { |profile| profile.fetch("id") } == %w[
      default-demo
      native-runtime-smoke
      standalone-host-example
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
    sbom_document = sbom(composition_document, inputs)
    validate_sbom(sbom_document, composition_document)
    outputs = {
      "COMPOSITION.json" => pretty_json(composition_document),
      "README.md" => readme,
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
    options = {check: false, validate_only: false}
    parser = OptionParser.new do |commands|
      commands.banner =
        "Usage: ruby Scripts/generate-release-compliance.rb [options]"
      commands.on("--check", "Check committed release-composition evidence") do
        options[:check] = true
      end
      commands.on("--validate-only", "Validate inputs without writing") do
        options[:validate_only] = true
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
      !options[:output].nil?
    ].count(true)
    unless modes == 1
      raise OptionParser::InvalidOption,
        "select exactly one of --check, --validate-only, or --output"
    end
    options
  end

  def execute(arguments)
    options = parse_options(arguments)
    if options.fetch(:check)
      check
      puts "Release composition inventory and SPDX SBOM are reproducible."
    elsif options.fetch(:validate_only)
      outputs = build_outputs
      sbom_document = JSON.parse(outputs.fetch("SBOM.spdx.json"))
      puts "Release composition inputs are valid " \
        "(#{sbom_document.fetch("packages").length} SPDX packages)."
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
