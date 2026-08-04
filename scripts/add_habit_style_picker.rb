#!/usr/bin/env ruby
# Adds Views/HabitStylePicker.swift to the Resistor target. Idempotent.
#
#   gem install xcodeproj && ruby scripts/add_habit_style_picker.rb

require 'xcodeproj'

project_path = File.expand_path('../Resistor.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'Resistor' } or abort 'No Resistor target'
views = project.main_group.find_subpath('Resistor/Views', true)

path = 'HabitStylePicker.swift'
ref = views.files.find { |f| f.path == path } || views.new_file(path)

if target.source_build_phase.files_references.include?(ref)
  puts "HabitStylePicker.swift already in Resistor"
else
  target.add_file_references([ref])
  puts "Added HabitStylePicker.swift to Resistor"
end

project.save
