#
# Bundles the prebuilt core as a dynamic framework
# (Frameworks/EmoConnectCore.xcframework, built on a Mac with
# tools/build_macos.sh). Nothing is compiled from source here.
#
Pod::Spec.new do |s|
  s.name             = 'emoconnect_sdk'
  s.version          = '0.2.0'
  s.summary          = 'EmoConnect SDK'
  s.description      = 'Connect to EmoConnect devices and receive PPG and motion data.'
  s.homepage         = 'https://newert.co.kr'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Newert' => 'joseph@newert.co.kr' }
  s.source           = { :path => '.' }
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.vendored_frameworks = 'Frameworks/EmoConnectCore.xcframework'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
