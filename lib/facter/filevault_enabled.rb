require 'puppet'

begin
  require 'osx/cocoa'
  include OSX
  require_framework('IOKit')
  require_framework('DiskArbitration')
  
  Facter.add('filevault_enabled') do
    confine :operatingsystem => :darwin
    result = false
    if Facter.macosx_productversion_major >= '10.7'
      url = CFURLCreateWithFileSystemPath(KCFAllocatorDefault, '/', KCFURLPOSIXPathStyle, true)
      session = DASessionCreate(KCFAllocatorDefault)
      disk = DADiskCreateFromVolumePath(KCFAllocatorDefault, session, url)
      diskService = DADiskCopyIOMedia(disk)
      if IORegistryEntryCreateCFProperty(diskService, 'CoreStorage Encrypted', KCFAllocatorDefault, 0)
        result = true
      end
    end
    setcode do
      result
    end
  end
  
rescue => LoadError
  puts "You shall not pass! [#{e.message}]"
end