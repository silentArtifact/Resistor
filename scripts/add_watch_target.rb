#!/usr/bin/env ruby
# Adds the ResistorWatch watchOS Quick-Log companion app target to
# Resistor.xcodeproj, wires its sources/Info.plist/entitlements/build settings,
# embeds it into the Resistor iOS app via an "Embed Watch Content" Copy Files
# phase, makes the iOS app depend on it, and makes the reused model + shared
# helper files members of the watch target so it compiles against the same
# CloudKit-compatible @Model types as the phone (NO file duplication).
#
# This is a single-target watchOS app (watchOS 9+ style:
# com.apple.product-type.application, SDKROOT = watchos), NOT the legacy
# WatchKit app+extension pair.
#
# Cross-device note: App Groups do NOT bridge iPhone and Apple Watch. The watch
# does NOT use the phone's app-group store (SharedModelContainer). It has its own
# local store wired against the same CloudKit container; CloudKit sync carries
# logs between devices. Hence this script does NOT add an app-group entitlement
# to the watch and does NOT add SharedModelContainer.swift to its membership.
#
# Idempotent: re-running does not duplicate the target, build phases, file
# references, memberships, or the shared scheme. Safe to run repeatedly.
#
# Requires the `xcodeproj` gem (gem install --user-install xcodeproj).

require "xcodeproj"

ROOT         = File.expand_path("..", __dir__)
PROJECT_PATH = File.join(ROOT, "Resistor.xcodeproj")
APP_TARGET   = "Resistor"
WATCH_TARGET = "ResistorWatch"
WATCH_DIR    = "ResistorWatch"
TEAM_ID      = "HBXLU45HR7"
APP_BUNDLE_ID   = "com.resistor.app"
WATCH_BUNDLE_ID = "#{APP_BUNDLE_ID}.watchkitapp"
WATCHOS_DEPLOYMENT_TARGET = "10.0"

# App/source files (relative to repo root) the watch target needs to compile
# because it reuses the app's @Model types and shared log helper. NOTE: this
# deliberately EXCLUDES SharedModelContainer.swift (app-group store the watch
# can't see) — the watch builds its own WatchModelContainer.
SHARED_APP_FILES = [
  "Resistor/Models/Habit.swift",
  "Resistor/Models/TemptationEvent.swift",
  "Resistor/Models/UserSettings.swift",
  "Resistor/Models/ContextTag.swift",
  "Resistor/Extensions/Color+Hex.swift",
  "Resistor/Shared/TemptationLogger.swift"
].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)

app = project.targets.find { |t| t.name == APP_TARGET }
raise "App target #{APP_TARGET} not found" unless app

# ---------------------------------------------------------------------------
# 1. Create (or reuse) the watchOS app target.
# ---------------------------------------------------------------------------
watch = project.targets.find { |t| t.name == WATCH_TARGET }
created = false
unless watch
  watch = project.new_target(
    :application,
    WATCH_TARGET,
    :watchos,
    WATCHOS_DEPLOYMENT_TARGET,
    nil,
    :swift
  )
  created = true
end

watch.build_configurations.each do |config|
  s = config.build_settings
  s["PRODUCT_NAME"]                      = "$(TARGET_NAME)"
  s["PRODUCT_BUNDLE_IDENTIFIER"]         = WATCH_BUNDLE_ID
  s["CODE_SIGN_STYLE"]                   = "Automatic"
  s["DEVELOPMENT_TEAM"]                  = TEAM_ID
  s["CODE_SIGN_ENTITLEMENTS"]            = "#{WATCH_DIR}/#{WATCH_TARGET}.entitlements"
  s["INFOPLIST_FILE"]                    = "#{WATCH_DIR}/Info.plist"
  s["GENERATE_INFOPLIST_FILE"]           = "YES"
  s["INFOPLIST_KEY_CFBundleDisplayName"] = "Resistor"
  s["INFOPLIST_KEY_WKApplication"]       = "YES"
  s["INFOPLIST_KEY_WKCompanionAppBundleIdentifier"] = APP_BUNDLE_ID
  s["INFOPLIST_KEY_UISupportedInterfaceOrientations"] = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown"
  s["SDKROOT"]                           = "watchos"
  s["WATCHOS_DEPLOYMENT_TARGET"]         = WATCHOS_DEPLOYMENT_TARGET
  s["TARGETED_DEVICE_FAMILY"]            = "4"
  s["SUPPORTED_PLATFORMS"]               = "watchos watchsimulator"
  s["SUPPORTS_MACCATALYST"]              = "NO"
  s["SWIFT_VERSION"]                     = "5.0"
  s["SWIFT_EMIT_LOC_STRINGS"]            = "YES"
  s["CURRENT_PROJECT_VERSION"]           = "1"
  s["MARKETING_VERSION"]                 = "1.0.0"
  s["SKIP_INSTALL"]                      = "YES"
  s["ENABLE_PREVIEWS"]                   = "YES"
  s["LD_RUNPATH_SEARCH_PATHS"]           = [
    "$(inherited)",
    "@executable_path/Frameworks"
  ]
end

# ---------------------------------------------------------------------------
# 2. Watch's own source group + files (everything under ResistorWatch/*.swift).
# ---------------------------------------------------------------------------
group = project.main_group.find_subpath(WATCH_DIR, true)
group.set_source_tree("<group>")
group.set_path(WATCH_DIR)

Dir.glob(File.join(ROOT, WATCH_DIR, "*.swift")).sort.each do |path|
  rel = File.basename(path)
  file_ref = group.files.find { |f| f.display_name == rel } || group.new_reference(rel)
  unless watch.source_build_phase.files_references.include?(file_ref)
    watch.add_file_references([file_ref])
  end
end

# Register Info.plist / entitlements as references (not compiled) if absent.
[["Info.plist"], ["#{WATCH_TARGET}.entitlements"]].each do |name,|
  next if group.files.any? { |f| f.display_name == name }
  group.new_reference(name)
end

# ---------------------------------------------------------------------------
# 3. Make the reused model/helper files members of the watch target too.
#    Reuse the existing file references already in the app target — no dupes.
# ---------------------------------------------------------------------------
SHARED_APP_FILES.each do |rel|
  ref = project.files.find { |f| f.real_path.to_s == File.join(ROOT, rel) }
  unless ref
    warn "WARNING: shared file reference not found for #{rel}; skipping membership."
    next
  end
  next if watch.source_build_phase.files_references.include?(ref)
  watch.add_file_references([ref])
end

# ---------------------------------------------------------------------------
# 4. Embed the watch app into the iOS app via an "Embed Watch Content" Copy
#    Files phase (dstSubfolderSpec 16 / path $(CONTENTS_FOLDER_PATH)/Watch).
# ---------------------------------------------------------------------------
embed_phase = app.copy_files_build_phases.find do |p|
  p.name == "Embed Watch Content" ||
    (p.dst_subfolder_spec.to_s == "16" && p.dst_path.to_s.include?("Watch"))
end
unless embed_phase
  embed_phase = app.new_copy_files_build_phase("Embed Watch Content")
  embed_phase.dst_subfolder_spec = "16"
  embed_phase.dst_path = "$(CONTENTS_FOLDER_PATH)/Watch"
end

product_ref = watch.product_reference
unless embed_phase.files_references.include?(product_ref)
  build_file = embed_phase.add_file_reference(product_ref, true)
  build_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
end

# The iOS app must build the watch app first (so it can embed it).
app.add_dependency(watch) unless app.dependencies.any? { |d| d.target == watch }

# ---------------------------------------------------------------------------
# 5. Dedicated shared scheme so the watch app is discoverable for xcodebuild.
# ---------------------------------------------------------------------------
scheme_path = File.join(
  PROJECT_PATH, "xcshareddata", "xcschemes", "#{WATCH_TARGET}.xcscheme"
)
unless File.exist?(scheme_path)
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(watch)
  scheme.set_launch_target(watch)
  scheme.save_as(PROJECT_PATH, WATCH_TARGET, true)
end

project.save

if created
  puts "Created #{WATCH_TARGET} watchOS app target, wired sources/shared files, embedded it in #{APP_TARGET}, and added a shared scheme."
else
  puts "#{WATCH_TARGET} already existed — refreshed sources, shared-file membership, embedding, and scheme (no duplicates)."
end
