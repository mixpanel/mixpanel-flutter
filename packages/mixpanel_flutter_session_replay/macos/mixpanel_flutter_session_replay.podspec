require 'yaml'
pubspec = YAML.load_file(File.join(__dir__, '..', 'pubspec.yaml'))

Pod::Spec.new do |s|
  s.name             = pubspec['name']
  s.version          = pubspec['version']
  s.summary          = 'Official Flutter Session Replay SDK for Mixpanel'
  s.description      = 'Official Flutter Session Replay SDK for Mixpanel, developed and maintained by Mixpanel, Inc.'
  s.homepage         = 'https://github.com/mixpanel/mixpanel-flutter/tree/main/packages/mixpanel_flutter_session_replay'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mixpanel' => 'support@mixpanel.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'mixpanel_flutter_session_replay/Sources/mixpanel_flutter_session_replay/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.14'
  s.swift_version    = '5.0'
end
