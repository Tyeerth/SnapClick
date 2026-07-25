#!/usr/bin/env ruby
require 'xcodeproj'

project_path = '/Users/tyeerth/Documents/MAC_software/SnapClick/SnapClick.xcodeproj'
project = Xcodeproj::Project.open(project_path)

recording_group = project.main_group['SnapClick']['Modules']['Recording']
main_target = project.targets.find { |t| t.name == 'SnapClick' }

name = 'RecordScreenPickerWindow.swift'

# 1) 从 Compile Sources 中移除
sources_phase = main_target.source_build_phase
build_file = sources_phase.files.find { |bf| bf.file_ref && bf.file_ref.path == name }
if build_file
  sources_phase.remove_build_file(build_file)
  puts "Removed #{name} from Compile Sources phase"
end

# 2) 从 group 中移除
file_ref = recording_group.files.find { |f| f.path == name }
if file_ref
  recording_group.remove_reference(file_ref)
  puts "Removed #{name} file ref from Recording group"
end

project.save
puts "Saved."
