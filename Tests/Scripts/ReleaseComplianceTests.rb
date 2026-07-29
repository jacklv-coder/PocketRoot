#!/usr/bin/env ruby

require "fileutils"
require "json"
require "minitest/autorun"
require "pathname"
require "tmpdir"
require_relative "../../Scripts/generate-release-compliance"

class ReleaseComplianceTests < Minitest::Test
  REPOSITORY_ROOT = Pathname(__dir__).join("../..").realpath
  INPUT_PATHS = [
    "LICENSE",
    "Package.resolved",
    "Package.swift",
    "project.yml",
    "Examples/PocketRootHostApp/project.yml",
    "Scripts/inject-demo-rootfs.sh",
    "Scripts/run-host-app-device-ui-smoke.sh",
    "Scripts/run-host-app-ui-smoke.sh",
    "ThirdPartyNotices/SwiftTerm-LICENSE.txt",
    "Compliance/RootFS/v0.3.3/EVIDENCE.json",
    "Compliance/RootFS/v0.3.3/SBOM.spdx.json"
  ].freeze

  def setup
    @temporary_directory =
      Pathname(Dir.mktmpdir("pocketroot-release-compliance-test-"))
  end

  def teardown
    FileUtils.remove_entry(@temporary_directory) if @temporary_directory.exist?
  end

  def test_checked_in_outputs_are_reproducible
    assert PocketRootReleaseCompliance.check
  end

  def test_json_formatting_is_independent_of_json_gem_pretty_defaults
    document = {
      "emptyArray" => [],
      "emptyObject" => {},
      "nested" => [
        {"value" => "line\n\t\"\\\u0001雪"}
      ],
      "flag" => false,
      "count" => 7,
      "fraction" => 1.25,
      "exponent" => 1.0e+20,
      "negativeZero" => -0.0,
      "nothing" => nil
    }
    expected = <<~'JSON'
      {
        "emptyArray": [],
        "emptyObject": {},
        "nested": [
          {
            "value": "line\n\t\"\\\u0001雪"
          }
        ],
        "flag": false,
        "count": 7,
        "fraction": 1.25,
        "exponent": 1.0e+20,
        "negativeZero": -0.0,
        "nothing": null
      }
    JSON

    rendered = PocketRootReleaseCompliance.pretty_json(document)

    assert_equal expected, rendered
    assert_equal document, JSON.parse(rendered)
  end

  def test_json_formatting_rejects_non_finite_numbers
    [Float::NAN, Float::INFINITY, -Float::INFINITY].each do |number|
      error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
        PocketRootReleaseCompliance.pretty_json({"number" => number})
      end

      assert_includes error.message, "must be finite"
    end
  end

  def test_full_graph_has_exact_packages_relationships_and_closed_gates
    outputs = PocketRootReleaseCompliance.build_outputs
    composition = JSON.parse(outputs.fetch("COMPOSITION.json"))
    sbom = JSON.parse(outputs.fetch("SBOM.spdx.json"))

    assert_equal 24, sbom.fetch("packages").length
    assert_equal(
      "dd2fb8ac5b861e7bf617c872895e338f38165648",
      composition.dig("externalComponents", "swiftTerm", "revision")
    )
    assert composition.dig(
      "externalComponents",
      "swiftArgumentParser",
      "resolvedOnly"
    )
    rootfs_package = sbom.fetch("packages").find do |package|
      package.fetch("SPDXID") == "SPDXRef-Package-External-RootFS"
    end
    assert_equal(
      "OPERATING_SYSTEM",
      rootfs_package.fetch("primaryPackagePurpose")
    )
    assert_equal 15, sbom.fetch("relationships").count { |relationship|
      relationship["spdxElementId"] ==
        "SPDXRef-Package-External-RootFS" &&
        relationship["relationshipType"] == "CONTAINS"
    }
    assert composition.dig("coverage", "releaseCompositionSBOMGenerated")
    refute composition.dig("coverage", "completeReleaseArtifactSBOM")
    refute composition.dig("coverage", "distributionAuthorized")
  end

  def test_default_demo_links_runtime_but_does_not_bundle_rootfs_by_default
    composition =
      JSON.parse(
        PocketRootReleaseCompliance.build_outputs.fetch("COMPOSITION.json")
      )
    default_profile =
      composition.fetch("profiles").find do |profile|
        profile.fetch("id") == "default-demo"
      end

    assert default_profile.fetch("includesIshRuntime")
    assert default_profile.fetch("requiresExternalRootFS")
    refute composition.dig(
      "externalComponents",
      "rootFS",
      "bundledByDefault"
    )
    refute composition.dig(
      "externalComponents",
      "rootFS",
      "downloadedByLibrary"
    )
  end

  def test_standalone_host_profile_uses_only_public_integration_products
    composition =
      JSON.parse(
        PocketRootReleaseCompliance.build_outputs.fetch("COMPOSITION.json")
      )
    host_profile =
      composition.fetch("profiles").find do |profile|
        profile.fetch("id") == "standalone-host-example"
      end

    assert_equal "PocketRootHostApp", host_profile.fetch("rootTarget")
    assert_equal(
      ["PocketRoot", "PocketRootIshRuntimeIntegration"],
      host_profile.fetch("swiftProducts")
    )
    assert host_profile.fetch("includesIshRuntime")
    assert host_profile.fetch("requiresExternalRootFS")
    refute host_profile.fetch("artifactBuiltAndScanned")
  end

  def test_standalone_host_retains_runtime_across_scene_recreation
    source =
      REPOSITORY_ROOT
        .join("Examples/PocketRootHostApp/Sources/HostApp.swift")
        .binread

    assert_match(
      /final class HostAppDelegate:.*?var workspaceHost:/m,
      source
    )
    assert_includes source, "HostViewController(runtimeOwner: appDelegate)"
    assert_includes source, "private unowned let runtimeOwner: HostAppDelegate"
    assert_includes source, "func sceneDidDisconnect(_ scene: UIScene)"
    assert_includes(
      source,
      "hostViewController.closeActiveInteractiveSurfaces()"
    )
    workspace_source =
      REPOSITORY_ROOT
        .join(
          "Sources/PocketRootTerminal/Public/" \
          "PocketRootWorkspaceViewController.swift"
        )
        .binread
    assert_includes workspace_source, "controller = current.parent"
    assert_includes workspace_source, "current.isMovingFromParent"
    assert_includes workspace_source, "current.isBeingDismissed"
    assert_includes source, "override func viewDidAppear(_ animated: Bool)"
    refute_includes source, "override func viewWillAppear(_ animated: Bool)"
    assert_match(
      /viewDidAppear.*?await workspaceHost\.refreshRuntimeState\(\)/m,
      source
    )

    info =
      REPOSITORY_ROOT
        .join("Examples/PocketRootHostApp/Sources/Info.plist")
        .binread
    assert_match(
      /<key>UIApplicationSupportsMultipleScenes<\/key>\s*<false\/>/,
      info
    )
  end

  def test_standalone_host_has_real_pty_and_files_ui_smoke
    project =
      REPOSITORY_ROOT
        .join("Examples/PocketRootHostApp/project.yml")
        .binread
    ui_test =
      REPOSITORY_ROOT
        .join(
          "Examples/PocketRootHostApp/UITests/PocketRootHostAppUITests.swift"
        )
        .binread
    host_source =
      REPOSITORY_ROOT
        .join("Examples/PocketRootHostApp/Sources/HostApp.swift")
        .binread
    runner =
      REPOSITORY_ROOT
        .join("Scripts/run-host-app-ui-smoke.sh")
        .binread
    device_runner =
      REPOSITORY_ROOT
        .join("Scripts/run-host-app-device-ui-smoke.sh")
        .binread
    workflow = REPOSITORY_ROOT.join(".github/workflows/ci.yml").binread

    assert_includes project, "PocketRootHostAppUITests:"
    assert_includes project, "type: bundle.ui-testing"
    assert_includes ui_test, "terminal.typeText("
    assert_includes ui_test, "PocketRootFiles.preview"
    assert_includes ui_test, "testPTYLifecycleAndShutdown"
    assert_includes ui_test, "testWorkspaceKeepsPTYAliveAcrossFilesTab"
    assert_includes(
      ui_test,
      "testIntegratedWorkspaceBootsAndOwnsShutdownOrdering"
    )
    assert_includes host_source, "PocketRootIshWorkspaceHost("
    assert_includes host_source, "workspaceHost.makeViewController()"
    assert_includes ui_test, "PocketRootHost.shutdown"
    assert_includes runner, "-test-timeouts-enabled YES"
    assert_includes device_runner, "build-for-testing"
    assert_includes device_runner, "test-without-building"
    assert_includes device_runner, "result.deviceProperties.osVersionNumber"
    assert_includes workflow, "./Scripts/run-host-app-ui-smoke.sh"
  end

  def test_rejects_demo_rootfs_injection_script_drift
    root = input_fixture
    path = root.join("Scripts/inject-demo-rootfs.sh")
    path.binwrite(
      path.binread.sub(
        'BUILD_CONFIGURATION="${CONFIGURATION:-Debug}"',
        'BUILD_CONFIGURATION="${CONFIGURATION:-Release}"'
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "repository input digest drifted"
  end

  def test_rejects_package_resolved_revision_drift
    root = input_fixture
    mutate_json(root.join("Package.resolved")) do |document|
      document.fetch("pins").fetch(0).fetch("state")["revision"] = "0" * 40
    end

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "Package.resolved external pins drifted"
  end

  def test_rejects_package_resolved_swiftterm_revision_drift
    root = input_fixture
    mutate_json(root.join("Package.resolved")) do |document|
      pin = document.fetch("pins").find do |candidate|
        candidate.fetch("identity") == "swiftterm"
      end
      pin.fetch("state")["revision"] = "0" * 40
    end

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "Package.resolved external pins drifted"
  end

  def test_rejects_package_resolved_origin_hash_drift
    root = input_fixture
    mutate_json(root.join("Package.resolved")) do |document|
      document["originHash"] = "0" * 64
    end

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "repository input digest drifted"
  end

  def test_rejects_package_manifest_product_drift
    root = input_fixture
    path = root.join("Package.swift")
    path.binwrite(
      path.binread.sub(
        'name: "PocketRootAgentRuntimeTools"',
        'name: "PocketRootAgentRuntimeToolsDrifted"'
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "Package.swift product graph drifted"
  end

  def test_rejects_unrecognized_package_product_and_target
    root = input_fixture
    path = root.join("Package.swift")
    contents = path.binread
    contents = contents.sub(
      "    products: [\n",
      "    products: [\n" \
        "        .executable(\n" \
        "            name: \"HiddenTool\",\n" \
        "            targets: [\"HiddenTool\"]\n" \
        "        ),\n"
    )
    contents = contents.sub(
      "    targets: [\n",
      "    targets: [\n" \
        "        .executableTarget(\n" \
        "            name: \"HiddenTool\"\n" \
        "        ),\n"
    )
    path.binwrite(contents)

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "unsupported product declaration"
  end

  def test_rejects_unrecognized_package_target_without_product
    root = input_fixture
    path = root.join("Package.swift")
    path.binwrite(
      path.binread.sub(
        "    targets: [\n",
        "    targets: [\n" \
          "        .executableTarget(name: \"HiddenTool\"),\n"
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "unsupported target declaration"
  end

  def test_rejects_unrecognized_package_dependency_form
    root = input_fixture
    path = root.join("Package.swift")
    path.binwrite(
      path.binread.sub(
        "    dependencies: [\n",
        "    dependencies: [\n" \
          "        .package(\n" \
          "            url: \"https://example.invalid/evil.git\",\n" \
          "            from: \"1.0.0\"\n" \
          "        ),\n"
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "external dependency declarations"
  end

  def test_rejects_unprojected_package_manifest_drift
    root = input_fixture
    path = root.join("Package.swift")
    contents = path.binread
    original = '.linkedLibrary("z")'
    assert_includes contents, original
    path.binwrite(contents.sub(original, '.linkedLibrary("sqlite3")'))

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "repository input digest drifted"
  end

  def test_rejects_package_target_dependency_drift
    root = input_fixture
    path = root.join("Package.swift")
    original =
      "\"PocketRootResources\"\n            ]\n        ),\n        .testTarget"
    replacement =
      original.sub(
        '"PocketRootResources"',
        '"PocketRootIshRuntimeIntegration"'
      )
    contents = path.binread
    assert_includes contents, original
    path.binwrite(contents.sub(original, replacement))

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "Package.swift target graph drifted"
  end

  def test_rejects_unparsed_package_target_dependency
    root = input_fixture
    path = root.join("Package.swift")
    path.binwrite(
      path.binread.sub(
        "\"PocketRootResources\"\n            ]\n        ),\n        .testTarget",
        "\"PocketRootResources\",\n" \
          "                .target(name: \"PocketRootIshRuntimeIntegration\")\n" \
          "            ]\n        ),\n        .testTarget"
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "unsupported dependency"
  end

  def test_rejects_package_test_target_dependency_drift
    root = input_fixture
    path = root.join("Package.swift")
    original =
      "\"PocketRootCore\"\n            ]\n        ),\n        .testTarget(\n" \
      "            name: \"PocketRootTerminalTests\""
    replacement =
      original.sub(
        '"PocketRootCore"',
        "\"PocketRootCore\",\n                \"PocketRootAgent\""
      )
    contents = path.binread
    assert_includes contents, original
    path.binwrite(contents.sub(original, replacement))

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "Package.swift test target graph drifted"
  end

  def test_rejects_application_product_composition_drift
    root = input_fixture
    path = root.join("project.yml")
    path.binwrite(
      path.binread.sub(
        "product: PocketRootIshRuntimeIntegration",
        "product: PocketRoot"
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "project.yml target composition drifted"
  end

  def test_rejects_application_resource_path_drift
    root = input_fixture
    path = root.join("project.yml")
    path.binwrite(
      path.binread.sub(
        "path: Demo/PocketRootDemo/Resources",
        "path: Spikes/PocketRootIshRuntimeSmoke"
      )
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "project.yml target composition drifted"
  end

  def test_rejects_application_target_deployment_floor_drift
    root = input_fixture
    path = root.join("project.yml")
    contents = path.binread
    original =
      "PocketRootDemo:\n    type: application\n    platform: iOS\n" \
      "    deploymentTarget: \"18.0\""
    assert_includes contents, original
    path.binwrite(
      contents.sub(original, original.sub('"18.0"', '"17.0"'))
    )

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "project.yml target composition drifted"
  end

  def test_rejects_effective_global_application_deployment_override
    root = input_fixture
    path = root.join("project.yml")
    contents = path.binread
    original = "    IPHONEOS_DEPLOYMENT_TARGET: \"18.0\""
    assert_includes contents, original
    path.binwrite(contents.sub(original, '    IPHONEOS_DEPLOYMENT_TARGET: "17.0"'))

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "exact project settings"
  end

  def test_rejects_effective_application_target_setting_override
    root = input_fixture
    path = root.join("project.yml")
    contents = path.binread
    original =
      "    settings:\n      base:\n" \
      "        PRODUCT_BUNDLE_IDENTIFIER: com.jacklv.PocketRootDemo\n"
    replacement =
      "    settings:\n      base:\n" \
      "        IPHONEOS_DEPLOYMENT_TARGET: \"17.0\"\n" \
      "        PRODUCT_BUNDLE_IDENTIFIER: com.jacklv.PocketRootDemo\n"
    assert_includes contents, original
    path.binwrite(contents.sub(original, replacement))

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "project.yml target composition drifted"
  end

  def test_rejects_unexpected_default_product_resource
    root = input_fixture
    root.join(
      "Demo/PocketRootDemo/Resources/unreviewed-fs.tar.gz"
    ).binwrite("payload")

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "default product resource tree drifted"
  end

  def test_rejects_top_level_license_gate_drift
    root = input_fixture
    root.join("LICENSE").binwrite("MIT License\n")

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "unfinalized-license gate"
  end

  def test_rejects_rootfs_distribution_approval_drift
    root = input_fixture
    mutate_json(
      root.join("Compliance/RootFS/v0.3.3/EVIDENCE.json")
    ) do |document|
      document.fetch("engineeringStatus")["redistributionApproved"] = true
    end

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "RootFS compliance evidence digest drifted"
  end

  def test_rejects_rootfs_package_coverage_drift
    root = input_fixture
    mutate_json(
      root.join("Compliance/RootFS/v0.3.3/SBOM.spdx.json")
    ) do |document|
      document.fetch("packages").pop
    end

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "RootFS compliance evidence digest drifted"
  end

  def test_rejects_rootfs_package_metadata_drift
    root = input_fixture
    mutate_json(
      root.join("Compliance/RootFS/v0.3.3/SBOM.spdx.json")
    ) do |document|
      document.fetch("packages").fetch(0)["name"] = "tampered"
    end

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.build_outputs(root)
    end

    assert_includes error.message, "RootFS compliance evidence digest drifted"
  end

  def test_rejects_runtime_rootfs_manifest_and_identity_gate_drift
    mutations = {
      "Sources/PocketRootResources/RootFSArtifactManifest.swift" => [
        'version: "v0.3.3"',
        'version: "v9.9.9"'
      ],
      "Sources/PocketRootIshRuntime/Public/" \
        "PocketRootIshRuntimeConfiguration.swift" => [
        'expectedOperatingSystemVersionID: "3.19.1"',
        'expectedOperatingSystemVersionID: "9.9.9"'
      ],
      "Sources/PocketRootIshRuntimeIntegration/" \
        "PocketRootIshSystemFactory.swift" => [
        "manifest == .ishEmbedV0_3_3 ? .ishEmbedV0_3_3 : .alpineARM64",
        "manifest == .ishEmbedV0_3_3 ? .alpineARM64 : .alpineARM64"
      ],
      "Sources/PocketRootIshRuntime/Runtime/IshRuntimeHealthCheck.swift" => [
        'configuration.expectedOperatingSystemID',
        '"tampered-operating-system-id"'
      ],
      "Sources/PocketRootResources/RootFSValidator.swift" => [
        "against manifest: PocketRootRootFSArtifactManifest = .ishEmbedV0_3_3",
        "against manifest: PocketRootRootFSArtifactManifest = .init("
      ],
      "Sources/PocketRootResources/RootFSInstaller.swift" => [
        "manifest: PocketRootRootFSArtifactManifest = .ishEmbedV0_3_3",
        "manifest: PocketRootRootFSArtifactManifest = .init("
      ]
    }

    mutations.each_with_index do |(relative, replacement), index|
      root = input_fixture("runtime-rootfs-#{index}")
      path = root.join(relative)
      contents = path.binread
      assert_includes contents, replacement.fetch(0)
      path.binwrite(contents.sub(*replacement))

      error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
        PocketRootReleaseCompliance.check(
          PocketRootReleaseCompliance.output_directory,
          root
        )
      end

      assert_includes error.message, "release compliance output is stale"
    end
  end

  def test_rejects_dangling_release_sbom_relationship
    outputs = PocketRootReleaseCompliance.build_outputs
    composition = JSON.parse(outputs.fetch("COMPOSITION.json"))
    sbom = JSON.parse(outputs.fetch("SBOM.spdx.json"))
    sbom.fetch("relationships").fetch(0)["relatedSpdxElement"] =
      "SPDXRef-Package-Missing"

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.validate_sbom(sbom, composition)
    end

    assert_includes error.message, "dangling ID"
  end

  def test_rejects_non_schema_spdx_package_purpose
    outputs = PocketRootReleaseCompliance.build_outputs
    composition = JSON.parse(outputs.fetch("COMPOSITION.json"))
    sbom = JSON.parse(outputs.fetch("SBOM.spdx.json"))
    rootfs_package = sbom.fetch("packages").find do |package|
      package.fetch("SPDXID") == "SPDXRef-Package-External-RootFS"
    end
    rootfs_package["primaryPackagePurpose"] = "OPERATING-SYSTEM"

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.validate_sbom(sbom, composition)
    end

    assert_includes error.message, "package analysis state drifted"
  end

  def test_rejects_release_authorization_gate_drift
    outputs = PocketRootReleaseCompliance.build_outputs
    composition = JSON.parse(outputs.fetch("COMPOSITION.json"))
    composition.fetch("coverage")["distributionAuthorized"] = true

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.validate_composition(composition)
    end

    assert_includes error.message, "exact coverage gates"
  end

  def test_materializes_new_external_directory_and_rejects_existing_output
    output = @temporary_directory.join("candidate")
    resolved_output = output.parent.realpath.join(output.basename)

    assert_equal resolved_output, PocketRootReleaseCompliance.materialize(output)
    assert_equal(
      PocketRootReleaseCompliance::OUTPUT_FILENAMES.sort,
      output.children.map { |path| path.basename.to_s }.sort
    )
    assert PocketRootReleaseCompliance.check(output)

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.materialize(output)
    end
    assert_includes error.message, "already exists"
  end

  def test_materialization_uses_one_resolved_parent
    real_parent = @temporary_directory.join("real-parent")
    real_parent.mkpath
    nested_parent = real_parent.join("nested")
    nested_parent.mkdir
    alias_parent = @temporary_directory.join("parent-alias")
    File.symlink(real_parent, alias_parent)
    requested_output = alias_parent.join("nested/candidate")
    resolved_output = nested_parent.realpath.join("candidate")

    assert_equal(
      resolved_output,
      PocketRootReleaseCompliance.materialize(requested_output)
    )
    assert resolved_output.directory?
    assert PocketRootReleaseCompliance.check(resolved_output)
  end

  def test_rejects_relative_and_in_repository_output_paths
    relative_error =
      assert_raises(PocketRootReleaseCompliance::ComplianceError) do
        PocketRootReleaseCompliance.materialize(Pathname("candidate"))
      end
    assert_includes relative_error.message, "must be absolute"

    repository_output =
      REPOSITORY_ROOT.join("Compliance/Release/test-materialization")
    repository_error =
      assert_raises(PocketRootReleaseCompliance::ComplianceError) do
        PocketRootReleaseCompliance.materialize(repository_output)
      end
    assert_includes repository_error.message, "outside the repository"
    refute repository_output.exist?
  end

  def test_check_rejects_an_unexpected_file
    output = @temporary_directory.join("candidate")
    PocketRootReleaseCompliance.materialize(output)
    output.join("unexpected.txt").binwrite("unexpected")

    error = assert_raises(PocketRootReleaseCompliance::ComplianceError) do
      PocketRootReleaseCompliance.check(output)
    end

    assert_includes error.message, "file set drifted"
  end

  private

  def input_fixture(name = "repository")
    root = @temporary_directory.join(name)
    root.mkpath
    INPUT_PATHS.each do |relative|
      source = REPOSITORY_ROOT.join(relative)
      destination = root.join(relative)
      destination.dirname.mkpath
      FileUtils.copy_file(source, destination)
    end
    PocketRootReleaseCompliance::IMPLEMENTATION_ROOTS.each do |relative|
      source = REPOSITORY_ROOT.join(relative)
      destination = root.join(relative)
      destination.dirname.mkpath
      FileUtils.cp_r(source, destination)
    end
    root
  end

  def mutate_json(path)
    document = JSON.parse(path.binread)
    yield document
    path.binwrite(PocketRootReleaseCompliance.pretty_json(document))
  end
end
