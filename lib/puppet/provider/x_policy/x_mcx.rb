# Provider: x_mcx
# Created: Wed Feb 15 07:49:15 PST 2012

# TODO
# - beef up MCX equality test so that it doean't re-apply everything if:
# => a) autocratic mode is 'false' AND b) policy has been changed locally
# => Right now, x_mcx will *always* re-apply policy if soemthing has been
# => changed locally. This is a result of the cheap and cheerful way we
# => compare state. To get around this, the comparsion needs to be able
# => to diff the two based on individual XML keys. I am not sure how to 
# => best accomplish this.
# => bcw

begin
  require 'tempfile'
  require 'osx/cocoa'
  include OSX
rescue LoadError
  puts "I feel like I'm taking crazy pills!"
end

Puppet::Type.type(:x_policy).provide(:x_mcx) do

  desc "MCX Settings management using DirectoryService on OS X.

  This provider manages the entire MCXSettings attribute available
  to some directory services nodes.  This management is 'all or nothing'
  in that discrete application domain key value pairs are not managed
  by this provider.

  Adapted from Jeff McCune's mcxcontent provider.
  "

  commands    :dscl => '/usr/bin/dscl'
  commands    :managedclient => '/System/Library/CoreServices/ManagedClient.app/Contents/MacOS/ManagedClient'
  confine     :operatingsystem => :darwin
  defaultfor  :operatingsystem => :darwin

  @@mcx_cache = '/Library/Managed Preferences'
  # This provides a mapping of puppet types to DirectoryService type strings.
  @@type_map = {
    :user          => 'Users',
    :group         => 'Groups',
    :computer      => 'Computers',
    :computergroup => 'ComputerGroups',
  }

  def create
    if resource[:autocratic]
      info("Autocratic mode: expunging previous policy")
      mcxdelete
    end
    info("Creating policy for #{resource[:name]}...")
    mcximport
    mcxrefresh
    5.times do |count|
      break if policy_cached?
      info("Waiting for Managed Preferences [#{count}] ...")
      mcxrefresh
    end
  end
  
  def destroy
    info("Destroying policy for #{resource[:name]}...")
    mcxdelete
  end

  # We define 'policy' as that which is authoritative whereas 'config' is present state
  def exists?
    info("Checking policy for #{resource[:name]}...")
    @kernel_version_major = Facter.kernelmajversion.to_i
    # Normalize the XML content by removing any whitespace fore and aft
    @policy = policy.split("\n").collect { |line| line.strip }.join("\n")
    @config = mcxexport.split("\n").collect { |line| line.strip }.join("\n")
    return false unless @config.eql?(@policy)
    true
  end

  # Returns the authoritative policy as specified in the Puppet resource
  def policy
    if resource[:plist]
      return File.readlines(resource[:plist]).to_s
    end 
    resource[:content]
  end
  
  def policy_cached?
    plist = NSDictionary.dictionaryWithContentsOfFile(resource[:plist])
    policy_files = plist.keys.collect { |policy| "#{@@mcx_cache}/#{policy}.plist" }
    policy_files.each do |file|
      unless File.exists?(file)
        puts "No such file: \'#{file}\'"
        return false
      end
    end
    true
  end
  
  # Abstracts dscl -mcxexport
  def mcxexport
    begin
      `dscl /Local/#{resource[:dslocal_node]} -mcxexport /#{@@type_map[resource[:type]]}/#{resource[:name]}`
    rescue Puppet::ExecutionFailure => detail
      fail("Could not export the MCX policy for #{resource[:name]}: #{detail}")
    end  
  end
  
  # Abstracts dscl -mcximport
  def mcximport
    tmp = Tempfile.new('puppet_mcx')
    policy = ""
    if resource[:plist]
      policy = resource[:plist]
    else
      tmp << resource[:content]
      tmp.flush
      policy = tmp.path
    end  
    begin
      dscl "/Local/#{resource[:dslocal_node]}", '-mcximport', "/#{@@type_map[resource[:type]]}/#{resource[:name]}", policy
      tmp.close
      tmp.unlink
    rescue Puppet::ExecutionFailure => detail
      fail("Could not import the MCX policy for #{resource[:name]}: #{detail}")
    end
  end
  
  def mcxrefresh
    managedclient '-f'
    sleep 5
  end
  
  def mcxdelete
    begin
      dscl "/Local/#{resource[:dslocal_node]}", '-mcxdelete', "/#{@@type_map[resource[:type]]}/#{resource[:name]}"
    rescue Puppet::ExecutionFailure => detail
      fail("Could not destroy the MCX policy for #{resource[:name]}: #{detail}")
    end
  end
    
end
