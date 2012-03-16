begin
  require 'osx/cocoa'
  include OSX
rescue LoadError
  puts "You're doing it wrong..."
end

Puppet::Type.type(:x_remotemanagement).provide(:x_remotemanagement) do

  commands    :kickstart       => '/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart'

  confine     :operatingsystem => :darwin
  defaultfor  :operatingsystem => :darwin

  has_feature :enableable

  @@path_to_user_plists = '/private/var/db/dslocal/nodes/Default/users'
  
  @@options = {'DirectoryGroupList'   => :dirgroups, 
    'DirectoryGroupLoginsEnabled'     => :dirlogins,
    'LoadRemoteManagementMenuExtra'   => :menuextra,
    'VNCLegacyConnectionsEnabled'     => :vnc,
    'ScreenSharingReqPermEnabled'     => :vncreqperm,
    'WBEMIncomingAccessEnabled'       => :webem
  }

  def start
    info("Starting RemoteAdministration service...")
    # If the service is running, stop and deactivate it
    begin
      kickstart "-deactivate", "-stop" #if running?
    rescue Puppet::ExecutionFailure
      raise Puppet::Error.new("Unable to stop service: #{resource[:name]} at path: #{job_path}")
    end
    
    # Configure the options specified in the Puppet resource
    @@options.each do |k,v|
      case resource[v]
      when true, :true, :enable, :enabled
	value = true
      when false, :false, :disable, :disabled,  nil
	value = false
      else
	value = resource[v]
      end
      @config[k] = value
    end

    # Configure access level
    if resource[:users].key?('all')
       @config['ARD_AllLocalUsers'] = true
       @config['ARD_AllLocalUsersPrivs'] = resource[:users]['all']
    else
       @config['ARD_AllLocalUsers'] = false
    end

    # Write the configuration to disk
    result = @config.writeToFile_atomically_(@preferences, true)
    raise("Could not write preferences to disk: writeToFile_atomically_ returned nil") if result.nil?
    
    # Deal with the VNC password, if required
    unless resource[:vncpass].empty?
      kickstart "-configure", "-clientopts", "-setvncpw", "-vncpw", resource[:vncpass] 
    end
    
    # Repair the required user accounts
    unless @users_to_repair.empty?
      unless @removals.empty?
        @removals.each do |account|
          # remove account attrib
          user = account[:name][0].to_ruby
	  info("Removing ARD privs for user, #{user}")
          account.delete('naprivs')
          result = account.writeToFile_atomically_("#{@@path_to_user_plists}/#{account[:name][0].to_ruby}.plist", true)
          raise("Could not write user plist to file: writeToFile_atomically_ returned nil") if result.nil?
        end
      end
      unless @additions.empty?
        @additions.each do |account|
          # add account attrib; has to an array of strings
          user = account[:name][0].to_ruby
	  privs = [resource[:users][user]]
	  info("Adding ARD privs, #{privs} for user, #{user} ")
          account['naprivs'] = privs
          result = account.writeToFile_atomically_("#{@@path_to_user_plists}/#{account[:name][0].to_ruby}.plist", true)
          raise("Could not write user plist to file: writeToFile_atomically_ returned nil") if result.nil?
        end
      end
    end
    
    # Start the service
    begin
      kickstart "-activate"
    rescue Puppet::ExecutionFailure
      raise Puppet::Error.new("Unable to stop service: #{resource[:name]} at path: #{job_path}")
    end
    
  end

  def stop
    info("Stopping RemoteAdministration service...")
    begin
      kickstart "-deactivate", "-stop"
    rescue Puppet::ExecutionFailure
      raise Puppet::Error.new("Unable to stop service: #{resource[:name]} at path: #{job_path}")
    end
  end

  def running?
    info("Checking RemoteAdministration service...")
    if configured? and status?
      return :running
    else
      return :stopped
    end
  end
  
  # Try and determine if RemoteManagement is already activated
  def status?
    # Is the VNC port open?
    unless system("nc -z localhost 5900 > /dev/null")
      info("VNC port not open...")
      return false
    end
    # Is at least one of the trigger files present?
    components = ['/Library/Preferences/com.apple.RemoteManagement.launchd', '/private/etc/RemoteManagement.launchd']
    components.each do |component|
	components.delete(component) if not File.exist?(component)
    end
    return false if components.empty?
    # Is the ARDAgent running?
    # This appears to be the only consistently active process on Leo, Snowy, and Lion.
    unless system("ps axc | grep ARDAgent > /dev/null")
      info("ARD agent not running...")
      return false
    end
    true
  end
  
  # Try and determine if RemoteManagement is already configured
  def configured?
    @config = load_config
    unless @config.nil?
      return unless priviledge_check
      @@options.each do |k,v|
        case resource[v]
        when true, :true, :enable, :enabled
          value = true
        when false, :false, :disable, :disabled,  nil
          value = false
        else
          value = resource[v]
        end
	config = @config.to_ruby
        return false unless config[k].eql?(value) 
      end
    else
      # Create a new configuration
      @config = NSMutableDictionary.new
      return unless priviledge_check
    end
    true
  end
  
  # Returns a BOOL but populates an array of user objects that require repair
  def priviledge_check
    # If we are allowing everybody to connect, then just check the 'everybody' settings
    @users_to_repair = []
    if resource[:users].key?('all')
      unless @config.empty?
	return false unless @config['ARD_AllLocalUsersPrivs']
        return false unless resource[:users]['all'].eql?(@config['ARD_AllLocalUsersPrivs'].to_ruby)
        return false unless @config['ARD_AllLocalUsers'].boolValue
        return true
      end
      return false
    end
    # If operation mode is autocratic, check all unscoped users for naprivs    
    @removals = []
    if resource[:autocratic]
      unscoped_users = all_users - resource[:users].keys
      unless unscoped_users.empty?
        unscoped_users.each do |user|
          user = get_user(user)
          @removals << user if user['naprivs']
        end
      end
    end
    # Always check scoped users
    @additions = []
    resource[:users].each do |k,v|
      user = get_user(k)
      if user['naprivs']
	unless user['naprivs'].to_ruby.to_s.eql?(v)
	  @additions << user 
	end
      else
	@additions << user 
      end
    end
    @users_to_repair = @additions + @removals
    return false unless @config['ARD_AllLocalUsers']
    unless @config['ARD_AllLocalUsers'].boolValue.eql?(true)
      return @users_to_repair.empty? 
    end
    false
  end
  
  # Returns an array containing the path to each eligible ARD user's plist file
  def all_users
    `dscl . list /Users`.split("\n").delete_if { |e| e =~ /^_/ }
  end
  
  # Load the user data
  ## Returns an NSDictionary representation of the the user.plist if it exists
  ## If it doesn't, it will return nil
  def get_user(name)
    file = "#{@@path_to_user_plists}/#{name}.plist"
    user = NSMutableDictionary.dictionaryWithContentsOfFile(file)
  end
  
  # Load the configuration data
  ## Returns an NSDictionary representation of the the preferences file if it exists
  ## If it doesn't, return nil
  def load_config
    @preferences = "/Library/Preferences/com.apple.RemoteManagement.plist"
    config = NSMutableDictionary.dictionaryWithContentsOfFile(@preferences)
  end

end
