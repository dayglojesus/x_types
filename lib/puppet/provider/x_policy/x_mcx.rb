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

require 'tempfile'

Puppet::Type.type(:x_policy).provide(:x_mcx) do

  desc "MCX Settings management using DirectoryService on OS X.

  This provider manages the entire MCXSettings attribute available
  to some directory services nodes.  This management is 'all or nothing'
  in that discrete application domain key value pairs are not managed
  by this provider.

  Adapted from Jeff McCune's mcxcontent provider.
  "

  # This provides a mapping of puppet types to DirectoryService type strings.
  @@type_map = {
    :user          => "Users",
    :group         => "Groups",
    :computer      => "Computers",
    :computergroup => "ComputerGroups",
  }

  commands    :dscl => "/usr/bin/dscl"
  confine     :operatingsystem => :darwin
  defaultfor  :operatingsystem => :darwin

  def create
    max_tries = 4
    count = 0
    if resource[:autocratic]
      info("Autocratic mode: expunging previous policy")
      self.destroy
    end
    info("Creating policy for #{resource[:name]}...")
    mcximport
    system("mcxquery -user root")
    while count <= max_tries
      File.exists?('/Library/Managed Preferences')
      info("Waiting for Managed Preferences...")
      mcxrefresh
      count += 1
    end
    unless File.exists?('/Library/Managed Preferences')
      notice("Policy application may require a reboot to ensure consistency.")
    end
    system("mcxquery -user root")
  end
  
  def destroy
    info("Destroying policy for #{resource[:name]}...")
    begin
      dscl "/Local/#{resource[:dslocal_node]}", '-mcxdelete', "/#{@@type_map[resource[:type]]}/#{resource[:name]}"
    rescue Puppet::ExecutionFailure => detail
      fail("Could not destroy the MCX policy for #{resource[:name]}: #{detail}")
    end
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
    policy = ""
    if resource[:plist]
      policy = File.readlines(resource[:plist]).to_s
    else 
      policy = resource[:content]
    end
    policy
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
    restart_directoryservices(10)
    system("mcxquery -user root &> /dev/null")
  end
  
  def restart_directoryservices(wait)
    if @kernel_version_major < 11
      system('/usr/bin/killall DirectoryService')
    else
      system('/usr/bin/killall opendirectoryd')
    end
    sleep wait
  end
  
end
