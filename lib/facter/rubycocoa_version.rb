require 'puppet'

Facter.add("rubycocoa_version") do
  confine :operatingsystem => :darwin
  rubycocoa_info_system = '/System/Library/Frameworks/RubyCocoa.framework/Resources/Info.plist'
  rubycocoa_info_global = '/Library/Frameworks/RubyCocoa.framework/Resources/Info.plist'
  if File.exists?(rubycocoa_info_global)
    @rubycocoa_vers = rubycocoa_info_global
  else
    @rubycocoa_vers = rubycocoa_info_system
  end
  setcode do
    `defaults read #{@rubycocoa_vers.gsub(File.extname(@rubycocoa_vers),"")} CFBundleVersion`
  end
end
