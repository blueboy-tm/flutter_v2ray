#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_v2ray.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_v2ray'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'

  # 添加 LibXray 静态库支持
  s.vendored_libraries = 'Frameworks/LibXray.xcframework/ios-arm64/libXray.a'
  s.static_framework    = true
  
  # Add LibXray headers
  s.source_files = 'Classes/**/*', 'Frameworks/LibXray.xcframework/ios-arm64/Headers/*.h'
  s.public_header_files = 'Frameworks/LibXray.xcframework/ios-arm64/Headers/*.h'

  # Add required system libraries for libXray
  s.libraries = 'resolv'
  
  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
