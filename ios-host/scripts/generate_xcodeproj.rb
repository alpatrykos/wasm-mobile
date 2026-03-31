#!/usr/bin/env ruby

require 'fileutils'
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'WasmMobile.xcodeproj')
DEPLOYMENT_TARGET = '18.0'
FRAMEWORK_TARGET_NAME = 'WasmMobileKit'
FRAMEWORK_PRODUCT_NAME = 'WasmMobile'
APP_TARGET_NAME = 'WasmMobileHost'
TEST_TARGET_NAME = 'WasmMobileDeviceTests'
SCHEME_NAME = 'WasmMobileDevice'

FRAMEWORK_SOURCE_PATHS = %w[
  Sources/WasmMobile/FeatureFlagModels.swift
  Sources/WasmMobile/FeatureFlagEngine.swift
  Sources/WasmMobile/WasmMobileResources.swift
  XcodeProject/WasmMobile/WasmHostRuntimeBridge.h
  XcodeProject/WasmMobile/WasmHostRuntimeBridge.m
  Sources/WasmHostBridge/vendor/host-bridge/wasm_host_runtime.c
  Sources/WasmHostBridge/vendor/wasm3/m3_bind.c
  Sources/WasmHostBridge/vendor/wasm3/m3_code.c
  Sources/WasmHostBridge/vendor/wasm3/m3_compile.c
  Sources/WasmHostBridge/vendor/wasm3/m3_core.c
  Sources/WasmHostBridge/vendor/wasm3/m3_env.c
  Sources/WasmHostBridge/vendor/wasm3/m3_exec.c
  Sources/WasmHostBridge/vendor/wasm3/m3_function.c
  Sources/WasmHostBridge/vendor/wasm3/m3_info.c
  Sources/WasmHostBridge/vendor/wasm3/m3_module.c
  Sources/WasmHostBridge/vendor/wasm3/m3_parse.c
  XcodeProject/WasmMobile/WasmMobile.h
].freeze

FRAMEWORK_RESOURCE_PATHS = [
  'Sources/WasmMobile/Resources/shared-core.wasm',
].freeze

APP_SOURCE_PATHS = [
  'XcodeProject/WasmMobileHost/AppMain.swift',
].freeze

TEST_SOURCE_PATHS = %w[
  Tests/WasmMobileTests/FeatureFlagEngineTests.swift
  Tests/WasmMobileTests/FeatureFlagBenchmarkTests.swift
].freeze

TEST_RESOURCE_PATHS = [
  '../fixtures/feature_flag_cases.json',
].freeze

def configure_build_settings(target, settings)
  target.build_configurations.each do |configuration|
    configuration.build_settings.merge!(settings)
  end
end

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes['LastSwiftUpdateCheck'] = '1600'
project.root_object.attributes['LastUpgradeCheck'] = '1600'
project.build_configuration_list.build_configurations.each do |configuration|
  configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
end

framework_target = project.new_target(
  :framework,
  FRAMEWORK_TARGET_NAME,
  :ios,
  DEPLOYMENT_TARGET,
  nil,
  :swift,
  FRAMEWORK_PRODUCT_NAME
)
app_target = project.new_target(:application, APP_TARGET_NAME, :ios, DEPLOYMENT_TARGET, nil, :swift)
test_target = project.new_target(:unit_test_bundle, TEST_TARGET_NAME, :ios, DEPLOYMENT_TARGET, nil, :swift)

framework_target.name = FRAMEWORK_TARGET_NAME
framework_target.product_name = FRAMEWORK_PRODUCT_NAME

framework_refs = FRAMEWORK_SOURCE_PATHS.map { |path| project.main_group.new_file(path) }
framework_target.add_file_references(framework_refs)
framework_resource_refs = FRAMEWORK_RESOURCE_PATHS.map { |path| project.main_group.new_file(path) }
framework_target.add_resources(framework_resource_refs)

app_refs = APP_SOURCE_PATHS.map { |path| project.main_group.new_file(path) }
app_target.add_file_references(app_refs)

test_refs = TEST_SOURCE_PATHS.map { |path| project.main_group.new_file(path) }
test_target.add_file_references(test_refs)
test_resource_refs = TEST_RESOURCE_PATHS.map { |path| project.main_group.new_file(path) }
test_target.add_resources(test_resource_refs)

framework_target.add_system_framework('Foundation')
app_target.add_system_framework('UIKit')
test_target.add_system_framework('UIKit')
test_target.add_system_framework('XCTest')

framework_product_ref = framework_target.product_reference
app_target.add_dependency(framework_target)
app_target.frameworks_build_phase.add_file_reference(framework_product_ref)
embed_phase = app_target.new_copy_files_build_phase('Embed Frameworks')
embed_phase.symbol_dst_subfolder_spec = :frameworks
embed_build_file = embed_phase.add_file_reference(framework_product_ref)
embed_build_file.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }

test_target.add_dependency(app_target)
test_target.add_dependency(framework_target)
test_target.frameworks_build_phase.add_file_reference(framework_product_ref)

common_ios_settings = {
  'SWIFT_VERSION' => '6.0',
  'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOYMENT_TARGET,
  'TARGETED_DEVICE_FAMILY' => '1',
  'CODE_SIGN_STYLE' => 'Automatic',
  'DEVELOPMENT_TEAM' => '$(IOS_DEVELOPMENT_TEAM)',
  'CODE_SIGN_IDENTITY[sdk=iphoneos*]' => '$(IOS_CODE_SIGN_IDENTITY)',
}

configure_build_settings(
  framework_target,
  common_ios_settings.merge(
    'PRODUCT_NAME' => FRAMEWORK_PRODUCT_NAME,
    'PRODUCT_MODULE_NAME' => FRAMEWORK_PRODUCT_NAME,
    'PRODUCT_BUNDLE_IDENTIFIER' => '$(BUNDLE_ID_PREFIX).framework',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => [
      '$(inherited)',
      '$(SRCROOT)/Sources/WasmHostBridge/include',
      '$(SRCROOT)/Sources/WasmHostBridge/vendor/host-bridge',
      '$(SRCROOT)/Sources/WasmHostBridge/vendor/wasm3',
    ],
    'SWIFT_OBJC_BRIDGING_HEADER' => 'XcodeProject/WasmMobile/WasmMobile-Bridging-Header.h',
    'SWIFT_OBJC_INTERFACE_HEADER_NAME' => 'WasmMobile-Swift.h',
    'SKIP_INSTALL' => 'NO',
  )
)

configure_build_settings(
  app_target,
  common_ios_settings.merge(
    'PRODUCT_BUNDLE_IDENTIFIER' => '$(BUNDLE_ID_PREFIX).host',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'NO',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/Frameworks',
  )
)

configure_build_settings(
  test_target,
  common_ios_settings.merge(
    'PRODUCT_BUNDLE_IDENTIFIER' => '$(BUNDLE_ID_PREFIX).device-tests',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/WasmMobileHost.app/WasmMobileHost',
    'BUNDLE_LOADER' => '$(TEST_HOST)',
    'TEST_TARGET_NAME' => APP_TARGET_NAME,
    'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/Frameworks @loader_path/Frameworks',
  )
)

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app_target, test_target, launch_target: true)
scheme.save_as(PROJECT_PATH, SCHEME_NAME, true)

project.sort
project.save
