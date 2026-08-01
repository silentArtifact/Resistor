#!/usr/bin/env ruby
# Adds the ResistorWatchComplication watchOS WidgetKit extension target to
# Resistor.xcodeproj, wires its source/Info.plist/build settings, embeds it in
# the ResistorWatch app (NOT the iOS app — a watch complication ships inside the
# watch app bundle's PlugIns) and makes ResistorWatch depend on it.
#
# The complication is a static launcher glyph only: a StaticConfiguration widget
# with a single timeline entry and a .never reload policy. It therefore needs NO
# shared source, NO entitlements, NO App Group, and NO SwiftData — tapping a
# complication launches its owning app automatically on watchOS, so there is
# nothing to read or write here. (Rendering today's resisted count would require
# moving the watch's local store into an App Group so the extension could read
# it; that is deliberately deferred.)
#
# Idempotent: re-running does not duplicate the target, build phases, file
# references, memberships, or the embed. Safe to run repeatedly.
#
# Requires the `xcodeproj` gem (gem install --user-install xcodeproj).

require "xcodeproj"

ROOT          = File.expand_path("..", __dir__)
PROJECT_PATH  = File.join(ROOT, "Resistor.xcodeproj")
WATCH_TARGET  = "ResistorWatch"
COMP_TARGET   = "ResistorWatchComplication"
COMP_DIR      = "ResistorWatchComplication"
TEAM_ID       = "HBXLU45HR7"
WATCH_BUNDLE_ID = "com.resistor.app.watchkitapp"
# NOT "#{WATCH_BUNDLE_ID}.complication": that exact string is unregistrable in
# the Developer portal ("is not available"), so no App ID can back it, so no
# distribution profile can be minted for it, so every Xcode Cloud Archive - iOS
# died at "Exporting for App Store Distribution failed". Locally it silently
# fell back to the team wildcard profile, which hides the problem in dev builds.
COMP_BUNDLE_ID  = "#{WATCH_BUNDLE_ID}.#{COMP_TARGET}"
WATCHOS_DEPLOYMENT_TARGET = "10.0"

project = Xcodeproj::Project.open(PROJECT_PATH)

watch = project.targets.find { |t| t.name == WATCH_TARGET }
raise "Watch target #{WATCH_TARGET} not found — run add_watch_target.rb first" unless watch

# ---------------------------------------------------------------------------
# 1. Create (or reuse) the watchOS app-extension target.
# ---------------------------------------------------------------------------
comp = project.targets.find { |t| t.name == COMP_TARGET }
created = false
unless comp
  comp = project.new_target(
    :app_extension,
    COMP_TARGET,
    :watchos,
    WATCHOS_DEPLOYMENT_TARGET,
    nil,
    :swift
  )
  created = true
end

comp.build_configurations.each do |config|
  s = config.build_settings
  s["PRODUCT_NAME"]                      = "$(TARGET_NAME)"
  s["PRODUCT_BUNDLE_IDENTIFIER"]         = COMP_BUNDLE_ID
  s["CODE_SIGN_STYLE"]                   = "Automatic"
  s["DEVELOPMENT_TEAM"]                  = TEAM_ID
  s["INFOPLIST_FILE"]                    = "#{COMP_DIR}/Info.plist"
  s["GENERATE_INFOPLIST_FILE"]           = "YES"
  s["INFOPLIST_KEY_CFBundleDisplayName"] = "Resistor"
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
  s["LD_RUNPATH_SEARCH_PATHS"]           = [
    "$(inherited)",
    "@executable_path/Frameworks",
    "@executable_path/../../Frameworks"
  ]
end

# ---------------------------------------------------------------------------
# 2. Complication's own source group + files (ResistorWatchComplication/*.swift).
# ---------------------------------------------------------------------------
group = project.main_group.find_subpath(COMP_DIR, true)
group.set_source_tree("<group>")
group.set_path(COMP_DIR)

Dir.glob(File.join(ROOT, COMP_DIR, "*.swift")).sort.each do |path|
  rel = File.basename(path)
  file_ref = group.files.find { |f| f.display_name == rel } || group.new_reference(rel)
  unless comp.source_build_phase.files_references.include?(file_ref)
    comp.add_file_references([file_ref])
  end
end

# Register Info.plist as a reference (not compiled) if absent. No entitlements
# file exists for this target by design.
group.new_reference("Info.plist") unless group.files.any? { |f| f.display_name == "Info.plist" }

# ---------------------------------------------------------------------------
# 3. Embed the extension in the WATCH app (Embed Foundation Extensions phase,
#    dstSubfolderSpec :plug_ins) and make the watch app build it first.
# ---------------------------------------------------------------------------
embed_phase = watch.copy_files_build_phases.find do |p|
  p.symbol_dst_subfolder_spec == :plug_ins
end
unless embed_phase
  embed_phase = watch.new_copy_files_build_phase("Embed Foundation Extensions")
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
end

product_ref = comp.product_reference
unless embed_phase.files_references.include?(product_ref)
  build_file = embed_phase.add_file_reference(product_ref, true)
  build_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
end

watch.add_dependency(comp) unless watch.dependencies.any? { |d| d.target == comp }

project.save

if created
  puts "Created #{COMP_TARGET} watchOS extension target, wired its source, and embedded it in #{WATCH_TARGET}."
else
  puts "#{COMP_TARGET} already existed — refreshed source membership and embedding (no duplicates)."
end
