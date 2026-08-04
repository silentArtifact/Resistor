#!/usr/bin/env ruby
# Adds the contact place-suggestion sources to the Xcode project (issue #78,
# Stage B). Idempotent — rerun if the file references are lost.
#
#   export GEM_HOME="$HOME/.gem/ruby/2.6.0"; export PATH="$GEM_HOME/bin:$PATH"
#   ruby scripts/add_contact_matching_files.rb
#
# ContactPlace.swift goes in the widget target too: it is part of
# SharedModelContainer's schema, which the widget compiles.

require 'xcodeproj'

project_path = File.expand_path('../Resistor.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

app = project.targets.find { |t| t.name == 'Resistor' }
widget = project.targets.find { |t| t.name == 'ResistorWidget' }
raise 'Resistor target not found' unless app

# path relative to the project root => targets that compile it
FILES = {
  'Resistor/Models/ContactPlace.swift' => [app, widget].compact,
  'Resistor/Services/ContactMatcher.swift' => [app]
}.freeze

FILES.each do |path, targets|
  basename = File.basename(path)
  group_path = File.dirname(path)

  group = project.main_group
  group_path.split('/').each do |component|
    group = group.find_subpath(component, true)
  end
  group.set_source_tree('<group>')

  file_ref = group.files.find { |f| f.path == basename } ||
             group.new_reference(basename)

  targets.each do |target|
    already = target.source_build_phase.files.any? { |bf| bf.file_ref == file_ref }
    next if already

    target.add_file_references([file_ref])
    puts "Added #{basename} to #{target.name}"
  end
end

# NSContactsUsageDescription: Contacts pre-matching (Stage B) calls
# CNContactStore.requestAccess. The contact *picker* needs no key — it runs out
# of process — so this covers only the opt-in Settings action.
app.build_configurations.each do |config|
  config.build_settings['INFOPLIST_KEY_NSContactsUsageDescription'] =
    'Used only if you turn on contact matching, to suggest a contact\'s name when you name a place. Addresses stay on this device.'
end

project.save
puts 'Saved project.'
