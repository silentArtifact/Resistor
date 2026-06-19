#!/usr/bin/env ruby
# Adds a ResistorUITests UI-testing target to Resistor.xcodeproj and wires it
# into the shared Resistor scheme so `xcodebuild test -only-testing:ResistorUITests`
# works. Idempotent: re-running it is a no-op if the target already exists.
#
# Requires the `xcodeproj` gem (gem install --user-install xcodeproj).

require "xcodeproj"

PROJECT_PATH = File.expand_path("../Resistor.xcodeproj", __dir__)
APP_TARGET   = "Resistor"
TEST_TARGET  = "ResistorUITests"
TEST_DIR     = "ResistorUITests"
TEAM_ID      = "HBXLU45HR7"

project = Xcodeproj::Project.open(PROJECT_PATH)

app = project.targets.find { |t| t.name == APP_TARGET }
raise "App target #{APP_TARGET} not found" unless app

if project.targets.any? { |t| t.name == TEST_TARGET }
  puts "Target #{TEST_TARGET} already exists — nothing to do."
  exit 0
end

test_target = project.new_target(
  :ui_test_bundle,
  TEST_TARGET,
  :ios,
  "17.0",
  nil,
  :swift
)

# Build settings for each configuration.
test_target.build_configurations.each do |config|
  s = config.build_settings
  s["PRODUCT_NAME"]                = "$(TARGET_NAME)"
  s["PRODUCT_BUNDLE_IDENTIFIER"]   = "com.resistor.app.ResistorUITests"
  s["TEST_TARGET_NAME"]            = APP_TARGET
  s["GENERATE_INFOPLIST_FILE"]     = "YES"
  s["CODE_SIGN_STYLE"]             = "Automatic"
  s["DEVELOPMENT_TEAM"]            = TEAM_ID
  s["IPHONEOS_DEPLOYMENT_TARGET"]  = "17.0"
  s["TARGETED_DEVICE_FAMILY"]      = "1"
  s["SWIFT_VERSION"]               = "5.0"
  s["SWIFT_EMIT_LOC_STRINGS"]      = "NO"
end

# Source files: add everything under ResistorUITests/. The group keeps its
# own path component so file references resolve to ResistorUITests/<file>.
group = project.main_group.find_subpath(TEST_DIR, true)
group.set_source_tree("<group>")
group.set_path(TEST_DIR)
Dir.glob(File.join(File.expand_path("../#{TEST_DIR}", __dir__), "*.swift")).sort.each do |path|
  rel = File.basename(path)
  next if group.files.any? { |f| f.display_name == rel }
  file_ref = group.new_reference(rel)
  test_target.add_file_references([file_ref])
end

# The UI-test target builds after the app it drives.
test_target.add_dependency(app)

# Create a DEDICATED shared scheme for the screenshot harness. Keeping it
# separate from the main "Resistor" scheme means unrelated unit-test compile
# breakage never blocks the UI screenshot run.
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(test_target)
scheme.set_launch_target(app)
scheme.save_as(PROJECT_PATH, TEST_TARGET, true)

project.save
puts "Added #{TEST_TARGET} target and wired it into the #{APP_TARGET} scheme."
