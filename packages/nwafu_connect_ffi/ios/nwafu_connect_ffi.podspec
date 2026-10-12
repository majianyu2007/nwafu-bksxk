Pod::Spec.new do |s|
  s.name             = 'nwafu_connect_ffi'
  s.version          = '0.1.0'
  s.summary          = 'Prebuilt nwafu-connect library'
  s.homepage         = 'https://github.com/majianyu2007/nwafu-connect'
  s.license          = { :type => 'AGPL-3.0' }
  s.author           = 'majianyu2007'
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.dependency 'Flutter'
  s.source_files     = 'Classes/**/*'
  fw = File.join(__dir__, '..', 'prebuilt', 'ios', 'NwafuConnect.xcframework')
  if File.exist?(fw)
    s.prepare_command = 'rm -rf NwafuConnect.xcframework && cp -R ../prebuilt/ios/NwafuConnect.xcframework .'
    s.vendored_frameworks = 'NwafuConnect.xcframework'
    s.preserve_paths = 'NwafuConnect.xcframework'
    # Keep the exported Nc* symbols for DynamicLibrary.process().
    s.user_target_xcconfig = { 'OTHER_LDFLAGS' => '-force_load "${PODS_XCFRAMEWORKS_BUILD_DIR}/nwafu_connect_ffi/libnwafuconnect.a" -lresolv' }
  end
end
