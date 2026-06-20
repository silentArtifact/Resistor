#!/usr/bin/env ruby
# Adds the ResistorWidget Home Screen widget extension target to
# Resistor.xcodeproj, wires its sources/Info.plist/entitlements/build settings,
# embeds it in the Resistor app target, and makes the shared model + helper
# files members of BOTH targets so the widget and app open the same App Group
# SwiftData store.
#
# Idempotent: re-running it does not duplicate the target, build phases, or file
# memberships. Safe to run repeatedly.
#
# Requires the `xcodeproj` gem (gem install --user-install xcodeproj).

require "xcodeproj"

ROOT          = File.expand_path("..", __dir__)
PROJECT_PATH  = File.join(ROOT, "Resistor.xcodeproj")
APP_TARGET    = "Resistor"
WIDGET_TARGET = "ResistorWidget"
WIDGET_DIR    = "ResistorWidget"
TEAM_ID       = "HBXLU45HR7"
APP_BUNDLE_ID = "com.resistor.app"
WIDGET_BUNDLE_ID = "#{APP_BUNDLE_ID}.ResistorWidget"

# App/source files (relative to repo root) that the widget target needs to
# compile because it reuses the app's models and shared helpers.
SHARED_APP_FILES = [
  "Resistor/Models/Habit.swift",
  "Resistor/Models/TemptationEvent.swift",
  "Resistor/Models/UserSettings.swift",
  "Resistor/Models/ContextTag.swift",
  "Resistor/Extensions/Color+Hex.swift",
  "Resistor/Shared/SharedModelContainer.swift",
  "Resistor/Shared/TemptationLogger.swift"
].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)

app = project.targets.find { |t| t.name == APP_TARGET }
raise "App target #{APP_TARGET} not found" unless app

# ---------------------------------------------------------------------------
# 1. Create (or reuse) the widget app-extension target.
# ---------------------------------------------------------------------------
widget = project.targets.find { |t| t.name == WIDGET_TARGET }
created = false
unless widget
  widget = project.new_target(
    :app_extension,
    WIDGET_TARGET,
    :ios,
    "17.0",
    nil,
    :swift
  )
  created = true
end

widget.build_configurations.each do |config|
  s = config.build_settings
  s["PRODUCT_NAME"]                       = "$(TARGET_NAME)"
  s["PRODUCT_BUNDLE_IDENTIFIER"]          = WIDGET_BUNDLE_ID
  s["CODE_SIGN_STYLE"]                    = "Automatic"
  s["DEVELOPMENT_TEAM"]                   = TEAM_ID
  s["CODE_SIGN_ENTITLEMENTS"]             = "#{WIDGET_DIR}/#{WIDGET_TARGET}.entitlements"
  s["INFOPLIST_FILE"]                     = "#{WIDGET_DIR}/Info.plist"
  s["GENERATE_INFOPLIST_FILE"]            = "YES"
  s["INFOPLIST_KEY_CFBundleDisplayName"]  = "Resistor"
  s["INFOPLIST_KEY_NSHumanReadableCopyright"] = ""
  s["IPHONEOS_DEPLOYMENT_TARGET"]         = "17.0"
  s["TARGETED_DEVICE_FAMILY"]             = "1"
  s["SUPPORTED_PLATFORMS"]                = "iphoneos iphonesimulator"
  s["SUPPORTS_MACCATALYST"]               = "NO"
  s["SWIFT_VERSION"]                      = "5.0"
  s["SWIFT_EMIT_LOC_STRINGS"]             = "YES"
  s["CURRENT_PROJECT_VERSION"]            = "1"
  s["MARKETING_VERSION"]                  = "1.0.0"
  s["LD_RUNPATH_SEARCH_PATHS"]            = [
    "$(inherited)",
    "@executable_path/Frameworks",
    "@executable_path/../../Frameworks"
  ]
  s["SKIP_INSTALL"]                       = "YES"
end

# ---------------------------------------------------------------------------
# 2. Widget's own source group + files (everything under ResistorWidget/*.swift).
# ---------------------------------------------------------------------------
group = project.main_group.find_subpath(WIDGET_DIR, true)
group.set_source_tree("<group>")
group.set_path(WIDGET_DIR)

Dir.glob(File.join(ROOT, WIDGET_DIR, "*.swift")).sort.each do |path|
  rel = File.basename(path)
  file_ref = group.files.find { |f| f.display_name == rel } || group.new_reference(rel)
  unless widget.source_build_phase.files_references.include?(file_ref)
    widget.add_file_references([file_ref])
  end
end

# Register Info.plist / entitlements as references (not compiled) if not present.
[["Info.plist"], ["#{WIDGET_TARGET}.entitlements"]].each do |name,|
  next if group.files.any? { |f| f.display_name == name }
  group.new_reference(name)
end

# ---------------------------------------------------------------------------
# 3a. Ensure the new Resistor/Shared/*.swift files exist as references in the
#     project and are members of the APP target (this project uses explicit
#     file references, not file-system-synchronized groups).
# ---------------------------------------------------------------------------
resistor_group = project.main_group.find_subpath("Resistor", false)
raise "Resistor group not found" unless resistor_group
shared_group = resistor_group.find_subpath("Shared", true)
shared_group.set_source_tree("<group>")
shared_group.set_path("Shared")

Dir.glob(File.join(ROOT, "Resistor/Shared", "*.swift")).sort.each do |path|
  base = File.basename(path)
  ref = shared_group.files.find { |f| f.display_name == base } ||
        project.files.find { |f| f.real_path.to_s == path }
  ref ||= shared_group.new_reference(base)
  unless app.source_build_phase.files_references.include?(ref)
    app.add_file_references([ref])
  end
end

# ---------------------------------------------------------------------------
# 3b. Make shared app/model/helper files members of the widget target too.
#     Reuse the existing file references already in the app target.
# ---------------------------------------------------------------------------
SHARED_APP_FILES.each do |rel|
  ref = project.files.find { |f| f.real_path.to_s == File.join(ROOT, rel) }
  unless ref
    warn "WARNING: shared file reference not found for #{rel}; skipping membership."
    next
  end
  next if widget.source_build_phase.files_references.include?(ref)
  widget.add_file_references([ref])
end

# ---------------------------------------------------------------------------
# 4. Embed the widget extension in the app (Embed App Extensions phase).
# ---------------------------------------------------------------------------
embed_phase = app.copy_files_build_phases.find do |p|
  p.symbol_dst_subfolder_spec == :plug_ins
end
unless embed_phase
  embed_phase = app.new_copy_files_build_phase("Embed Foundation Extensions")
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
end

product_ref = widget.product_reference
already_embedded = embed_phase.files_references.include?(product_ref)
unless already_embedded
  build_file = embed_phase.add_file_reference(product_ref, true)
  build_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
end

# The app must build the widget first.
app.add_dependency(widget) unless app.dependencies.any? { |d| d.target == widget }

project.save

if created
  puts "Created #{WIDGET_TARGET} extension target, wired sources/shared files, and embedded it in #{APP_TARGET}."
else
  puts "#{WIDGET_TARGET} already existed — refreshed sources, shared-file membership, and embedding (no duplicates)."
end
