#!/usr/bin/env ruby
# frozen_string_literal: true
# Add a LiveTests target to the CopilotMonitor Xcode project, and move
# TavilyLiveIntegrationTests.swift out of the default test target so that
# the default scheme does not hit the live network.
#
# Also fixes a pre-existing pbxproj bug: a single PBXBuildFile UUID was
# referenced by two PBXSourcesBuildPhase sections, which is not legal pbxproj
# and makes xcodeproj refuse to save the project. We split such duplicates
# into two build files that both point at the same PBXFileReference.

require 'xcodeproj'
require 'fileutils'

PROJECT_PATH = 'CopilotMonitor/CopilotMonitor.xcodeproj'
LIVE_TEST_NAME = 'TavilyLiveIntegrationTests.swift'

project = Xcodeproj::Project.open(PROJECT_PATH)

# ---------------------------------------------------------------------------
# Phase 0: fix duplicate build file references in the same project.
# Find any build file that is referenced from more than one source phase and
# create a duplicate build file for the second (and subsequent) occurrence.
# ---------------------------------------------------------------------------
build_file_to_phases = Hash.new { |h, k| h[k] = [] }
project.objects.each do |obj|
  next unless obj.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase)
  obj.files.each do |bf|
    build_file_to_phases[bf] << obj
  end
end

duplicates = build_file_to_phases.select { |_bf, phases| phases.size > 1 }
unless duplicates.empty?
  puts "Found #{duplicates.size} duplicate build file(s); splitting them."
end

duplicates.each do |bf, phases|
  ref = bf.file_ref
  raise "Duplicate build file #{bf.uuid} has nil file_ref" unless ref

  # Keep the first occurrence; create a fresh build file for the rest.
  phases[1..].each do |phase|
    phase.remove_build_file(bf)
    phase.add_file_reference(ref)
    puts "  split #{ref.path}: kept #{bf.uuid} in one phase, added new build file in another"
  end
end

# ---------------------------------------------------------------------------
# Phase 0.5: ensure shared utility files are present in every target that
# originally referenced them. The pre-existing duplicate fix above removes
# the build file from any phase it shouldn't belong to; we compensate by
# detecting which target lost the file and re-adding it.
# ---------------------------------------------------------------------------
# Files we know should be in both the main app target and the opencodebar-cli
# target. This list is intentionally small and explicit; if a future file
# needs to be shared, add it here.
SHARED_UTILITY_FILES = ['TimeZone+UTC.swift'].freeze
SHARED_UTILITY_OWNERS = ['CopilotMonitor', 'opencodebar-cli'].freeze

# Tracks whether the re-add phase made any modifications.
re_added_any = false

SHARED_UTILITY_FILES.each do |filename|
  ref = project.objects.find do |o|
    o.is_a?(Xcodeproj::Project::Object::PBXFileReference) &&
      o.respond_to?(:path) &&
      o.path == filename
  end
  next unless ref

  SHARED_UTILITY_OWNERS.each do |target_name|
    target = project.targets.find { |t| t.name == target_name }
    next unless target

    already = target.source_build_phase.files.any? { |bf| bf.file_ref == ref }
    next if already

    target.source_build_phase.add_file_reference(ref)
    re_added_any = true
    puts "  re-added #{filename} to #{target_name}"
  end
end

# If we re-added something AND the LiveTests target already exists, we still
# need to save the project (the re-add modified the in-memory state).
need_save = re_added_any


# ---------------------------------------------------------------------------
# Phase 1: locate the live test file ref & build file in the default tests
# target, then move it into a new LiveTests target.
# ---------------------------------------------------------------------------
if project.targets.any? { |t| t.name == 'LiveTests' }
  if need_save
    project.save
    puts 'LiveTests target already exists; saved re-added shared utility files.'
  else
    puts 'LiveTests target already exists; nothing to do.'
  end
  exit 0
end

main_group = project.main_group
products_group = main_group['Products']
frameworks_group = main_group['Frameworks']

app_target = project.targets.find { |t| t.name == 'CopilotMonitor' }
test_target = project.targets.find { |t| t.name == 'CopilotMonitorTests' }
raise 'CopilotMonitor target not found' unless app_target
raise 'CopilotMonitorTests target not found' unless test_target

# 1. Find the live test file ref & build file in the default test target
live_ref = test_target.source_build_phase.files_references.find do |r|
  r.path == LIVE_TEST_NAME
end
raise "Could not find #{LIVE_TEST_NAME} in CopilotMonitorTests" unless live_ref

live_build_file = test_target.source_build_phase.files.find do |bf|
  bf.file_ref == live_ref
end
raise "Could not find build file for #{LIVE_TEST_NAME}" unless live_build_file

puts "Found live test build file: #{live_build_file.uuid}"

# 2. Add a LiveTests group under main_group (mirror CopilotMonitorTests style)
live_group = main_group.new_group('LiveTests', 'LiveTests', :group)
puts "Created LiveTests group at #{live_group.real_path}"

# We deliberately do NOT move the file ref. The reference still lives in
# CopilotMonitorTests (so it shows up in Xcode there), but only the
# LiveTests target will actually compile it. Target membership is the
# isolation mechanism, not file system location.

# 3. Create the LiveTests target. The platform must be :osx because the rest
#    of the project is a macOS app and the test bundle must match.
live_target = project.new_target(
  :unit_test_bundle,
  'LiveTests',
  :osx,
  '13.0',
  project.products_group,
  :swift
)
puts "Created LiveTests target: #{live_target.uuid} (#{live_target.product_type})"

# 4. Build settings: clone CopilotMonitorTests, add LIVE_TESTS macro and
#    set a distinct bundle id.
src_settings = test_target.build_configurations.first.build_settings.dup
src_settings.each do |k, _v|
  # Will be set explicitly below; skip keys we are overriding.
end
src_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.tokenking.app.livetests'
src_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) LIVE_TESTS'
src_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
src_settings['SDKROOT'] = 'macosx'
src_settings['SUPPORTED_PLATFORMS'] = 'macosx'
src_settings['SUPPORTS_MACCATALYST'] = 'NO'
src_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
src_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Token King.app/Contents/MacOS/Token King'
# Use the same scheme/test infra
src_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
src_settings['CODE_SIGN_STYLE'] = 'Automatic'
src_settings['DEVELOPMENT_TEAM'] = ''

live_target.build_configurations.each do |config|
  src_settings.each { |k, v| config.build_settings[k] = v }
end
puts 'Configured build settings for LiveTests target'

# 5. Add target dependency on the app so it can @testable import
container_proxy = project.new(Xcodeproj::Project::Object::PBXContainerItemProxy)
container_proxy.container_portal = project.root_object.uuid
container_proxy.proxy_type = '1'
container_proxy.remote_global_id_string = app_target.uuid
container_proxy.remote_info = 'CopilotMonitor'

dependency = project.new(Xcodeproj::Project::Object::PBXTargetDependency)
dependency.target = app_target
dependency.target_proxy = container_proxy
live_target.dependencies << dependency
puts "Added dependency on CopilotMonitor"

# 6. Move the live test build file from the default test target to LiveTests
test_target.source_build_phase.remove_build_file(live_build_file)
puts "Removed build file from CopilotMonitorTests source phase"

# Add the same file ref to LiveTests source phase
new_build_file = live_target.source_build_phase.add_file_reference(live_ref)
puts "Added build file to LiveTests source phase: #{new_build_file.uuid}"

# 7. Add the new product reference to products group (xcodeproj usually does
#    this automatically, but be explicit)
products_group << live_target.product_reference unless products_group.children.include?(live_target.product_reference)

# 8. Re-register LiveTests as a project target (it is auto-added by
#    new_target, but ensure ordering).
unless project.targets.include?(live_target)
  project.targets << live_target
end
puts "Project targets: #{project.targets.map(&:name).join(', ')}"

project.save
puts "Saved #{PROJECT_PATH}"

# ---------------------------------------------------------------------------
# Phase 9: write the LiveTests xcscheme if it doesn't already exist or if it
# is out of date. The BlueprintIdentifier must match the LiveTests target's
# UUID; we generate a stable scheme by patching the UUID into the template.
# ---------------------------------------------------------------------------
scheme_dir = File.join(PROJECT_PATH, 'xcshareddata', 'xcschemes')
scheme_path = File.join(scheme_dir, 'LiveTests.xcscheme')
FileUtils.mkdir_p(scheme_dir)

live_target_uuid = live_target.uuid
template = <<~SCHEME
  <?xml version="1.0" encoding="UTF-8"?>
  <Scheme LastUpgradeVersion="1500" version="1.7">
     <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
        <BuildActionEntries>
           <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
              <BuildableReference
                 BuildableIdentifier="primary"
                 BlueprintIdentifier="AFFFFFFFFFFFFFFFFFFFFF"
                 BuildableName="Token King.app"
                 BlueprintName="CopilotMonitor"
                 ReferencedContainer="container:CopilotMonitor.xcodeproj">
              </BuildableReference>
           </BuildActionEntry>
        </BuildActionEntries>
     </BuildAction>
     <TestAction
        buildConfiguration="Debug"
        selectedDebugger="Xcode.DebuggerFoundation.Debugger.LLDB"
        selectedLauncher="Xcode.LauncherFoundation.Launcher.LLDB"
        shouldUseLaunchSchemeArgsEnv="YES"
        shouldAutocreateTestPlan="YES">
        <Testables>
           <TestableReference
              skipped="NO"
              parallelizable="NO">
              <BuildableReference
                 BuildableIdentifier="primary"
                 BlueprintIdentifier="LIVE_TARGET_UUID"
                 BuildableName="LiveTests.xctest"
                 BlueprintName="LiveTests"
                 ReferencedContainer="container:CopilotMonitor.xcodeproj">
              </BuildableReference>
           </TestableReference>
        </Testables>
     </TestAction>
     <LaunchAction
        buildConfiguration="Debug"
        selectedDebugger="Xcode.DebuggerFoundation.Debugger.LLDB"
        selectedLauncher="Xcode.LauncherFoundation.Launcher.LLDB"
        launchStyle="0"
        useCustomWorkingDir="NO"
        ignoresPersistentStateOnLaunch="NO"
        debugDocumentVersioning="YES"
        debugServiceExtension="internal"
        allowLocationSimulation="NO"
        viewDebuggingEnabled="No">
        <BuildableProductRunnable
           runnableDebuggingMode="0">
           <BuildableReference
              BuildableIdentifier="primary"
              BlueprintIdentifier="AFFFFFFFFFFFFFFFFFFFFF"
              BuildableName="Token King.app"
              BlueprintName="CopilotMonitor"
              ReferencedContainer="container:CopilotMonitor.xcodeproj">
           </BuildableReference>
        </BuildableProductRunnable>
     </LaunchAction>
     <ProfileAction
        buildConfiguration="Release"
        shouldUseLaunchSchemeArgsEnv="YES"
        savedToolIdentifier=""
        useCustomWorkingDir="NO"
        debugDocumentVersioning="YES">
        <BuildableProductRunnable
           runnableDebuggingMode="0">
           <BuildableReference
              BuildableIdentifier="primary"
              BlueprintIdentifier="AFFFFFFFFFFFFFFFFFFFFF"
              BuildableName="Token King.app"
              BlueprintName="CopilotMonitor"
              ReferencedContainer="container:CopilotMonitor.xcodeproj">
           </BuildableReference>
        </BuildableProductRunnable>
     </ProfileAction>
     <AnalyzeAction
        buildConfiguration="Debug">
     </AnalyzeAction>
     <ArchiveAction
        buildConfiguration="Release"
        revealArchiveInOrganizer="YES">
     </ArchiveAction>
  </Scheme>
SCHEME

content = template.gsub('LIVE_TARGET_UUID', live_target_uuid)
File.write(scheme_path, content)
puts "Wrote scheme #{scheme_path}"
