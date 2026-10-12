Pod::Spec.new do |s|
  s.name             = 'nwafu_connect_ffi'
  s.version          = '0.1.0'
  s.summary          = 'Prebuilt nwafu-connect library'
  s.homepage         = 'https://github.com/majianyu2007/nwafu-connect'
  s.license          = { :type => 'AGPL-3.0' }
  s.author           = 'majianyu2007'
  s.source           = { :path => '.' }
  s.platform         = :osx, '14.0'
  s.dependency 'FlutterMacOS'
  s.source_files     = 'Classes/**/*'
  lib = File.join(__dir__, '..', 'prebuilt', 'macos', 'libnwafuconnect.dylib')
  if File.exist?(lib)
    s.vendored_libraries = 'libnwafuconnect.dylib'
    s.prepare_command = 'cp ../prebuilt/macos/libnwafuconnect.dylib .'
    s.preserve_paths = 'libnwafuconnect.dylib'
  end
end
