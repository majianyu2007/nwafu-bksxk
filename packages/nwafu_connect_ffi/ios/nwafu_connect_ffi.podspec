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
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  # tool/build-vpn-lib.sh ios copies the xcframework next to this podspec.
  fw = File.join(__dir__, 'NwafuConnect.xcframework')
  if File.exist?(fw)
    s.vendored_frameworks = 'NwafuConnect.xcframework'
    s.preserve_paths = 'NwafuConnect.xcframework'
    # Go's runtime needs libresolv; Classes/NwafuConnectKeep.m keeps the Nc*
    # symbols that DynamicLibrary.process() looks up at run time.
    s.libraries = 'resolv'
  else
    # No prebuilt library: compile without the keep-alive references.
    s.exclude_files = 'Classes/NwafuConnectKeep.m'
  end
end
