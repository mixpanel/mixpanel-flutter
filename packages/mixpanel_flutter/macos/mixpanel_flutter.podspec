#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint mixpanel_flutter.podspec' to validate before publishing.
#
require 'yaml'
pubspec = YAML.load_file(File.join(__dir__, '..', 'pubspec.yaml'))

Pod::Spec.new do |s|
  s.name             = pubspec['name']
  s.version          = pubspec['version']
  s.summary          = 'Official Flutter Tracking Library for Mixpanel Analytics'
  s.homepage         = 'https://www.mixpanel.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mixpanel, Inc' => 'support@mixpanel.com' }
  s.source           = { :path => '.' }
  s.source_files = 'mixpanel_flutter/Sources/mixpanel_flutter/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.dependency 'Mixpanel-swift', '6.4.1'
  # Explicit dependency (also pulled in transitively by Mixpanel-swift 6.4+)
  # so `import MixpanelSwiftCommon` in our plugin resolves reliably.
  s.dependency 'MixpanelSwiftCommon', '~> 1.0.1'
  s.platform = :osx, '10.15'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
