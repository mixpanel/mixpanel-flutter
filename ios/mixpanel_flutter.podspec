#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint mixpanel_flutter.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'mixpanel_flutter'
  s.version          = '2.3.1'
  s.summary          = 'Official Flutter Tracking Library for Mixpanel Analytics'
  s.homepage         = 'https://www.mixpanel.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mixpanel, Inc' => 'support@mixpanel.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'Mixpanel-swift', '4.2.5'
  s.platform = :ios, '11.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
