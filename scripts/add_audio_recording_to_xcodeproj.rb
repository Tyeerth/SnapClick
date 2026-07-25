#!/usr/bin/env ruby
require 'xcodeproj'

project_path = '/Users/tyeerth/Documents/MAC_software/SnapClick/SnapClick.xcodeproj'
project = Xcodeproj::Project.open(project_path)

modules_group = project.main_group['SnapClick']['Modules']
raise "Modules group not found" unless modules_group

main_target = project.targets.find { |t| t.name == 'SnapClick' }
raise "Main target not found" unless main_target

# 创建或获取 AudioRecording group
audio_group = modules_group['AudioRecording']
unless audio_group
  audio_group = modules_group.new_group('AudioRecording', 'AudioRecording')
  puts "Created AudioRecording group"
end

# 添加文件
files = %w[
  AudioQualitySettings.swift
  AudioLevelMeter.swift
  AudioRecordingEngine.swift
  AudioRecordingPreviewCard.swift
  AudioRecordingSettingsView.swift
  AudioRecordingHUDWindow.swift
  AudioMicrophoneTestEngine.swift
  AudioMicrophoneTestCard.swift
]

files.each do |name|
  ref = audio_group.files.find { |f| f.path == name }
  unless ref
    ref = audio_group.new_file(name)
    puts "Added file ref: #{name}"
  end
  unless main_target.source_build_phase.files_references.include?(ref)
    main_target.add_file_references([ref])
    puts "Added to target: #{name}"
  end
end

project.save
puts "Saved."
