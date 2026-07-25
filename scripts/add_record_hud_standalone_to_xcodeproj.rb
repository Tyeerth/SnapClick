#!/usr/bin/env ruby
require 'xcodeproj'

project_path = '/Users/tyeerth/Documents/MAC_software/SnapClick/SnapClick.xcodeproj'
project = Xcodeproj::Project.open(project_path)

recording_group = project.main_group['SnapClick']['Modules']['Recording']
raise "Recording group not found" unless recording_group

main_target    = project.targets.find { |t| t.name == 'SnapClick' }
raise "Main target not found" unless main_target

%w[RecordHUDStandaloneWindow.swift].each do |name|
  ref = recording_group.files.find { |f| f.path == name }
  unless ref
    ref = recording_group.new_file(name)
    puts "Added #{name} file ref"
  end
  unless main_target.source_build_phase.files_references.include?(ref)
    main_target.add_file_references([ref])
    puts "Added #{name} to target: #{main_target.name}"
  end
end

project.save
puts "Saved."
