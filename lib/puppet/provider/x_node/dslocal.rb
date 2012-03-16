begin
  require 'fileutils'
  require 'osx/cocoa'
  include OSX
rescue LoadError
  puts "Move along, nothing to see here."
end

# Provider: dslocal_node
# TODO
# - do full scan of all files in the node to ensure ownership and perms are correct
Puppet::Type.type(:x_node).provide(:dslocal) do
  desc 'Provides interface for managing Mac OS X Local Directory Service nodes.'

  commands  :dsclcmd          => '/usr/bin/dscl'
  confine   :operatingsystem  => :darwin

  DSLOCAL_NODE  = '/Local/Default'
  BSD_NODE      = '/BSD/local'
  DSLOCAL_ROOT  = '/private/var/db/dslocal/nodes'
  CHILD_DIRS    = ['aliases', 'computer_lists', 'computergroups', 'computers', 'config', 'groups', 'networks', 'users']
  DIRMODE       = 16832
  FILEMODE      = 33152
  SP_CUSTOM     = 'dsAttrTypeStandard:CSPSearchPath'
  
  def create
    info("Creating local node: #{resource[:name]}")
    # Create the node, if it's not already present
    begin
      FileUtils.mkdir_p("#{@parent}") unless File.exist?("#{@parent}")
      FileUtils.chmod(0700, "#{@parent}")
      CHILD_DIRS.each do |child|
        FileUtils.mkdir_p("#{@parent}/#{child}") unless File.exist?("#{@parent}/#{child}")
        FileUtils.chmod(0700, "#{@parent}/#{child}")
      end
      FileUtils.chown_R('root', 'wheel', "#{@parent}")
    rescue Exception => e  
      p e.message  
      # p e.backtrace.inspect
    end
    # Activate the node by appending the search path if requested
    @searchpath.delete(@our_node)
    if resource[:active].eql?(:true)
      if index = @searchpath.index(BSD_NODE)
	@searchpath.insert(index + 1, @our_node)
      else
	@searchpath.insert(1, @our_node)
      end
    end
    restart_directoryservices(5)
    return unless set_cspsearchpath(@searchpath)
    return unless set_searchpolicy(SP_CUSTOM)
  end

  def destroy
    info("Destroying local node: #{resource[:name]}")
    FileUtils.rm_rf(@parent) if File.exist?("#{@parent}")
    @searchpath.delete(@our_node)
    return unless set_cspsearchpath(@searchpath)
  end

  def exists?
    info("Checking local node: #{resource[:name]}")
    @our_node = "/Local/#{resource[:name]}"
    @parent   = "#{DSLOCAL_ROOT}/#{resource[:name]}"
    return false unless @searchpath = get_cspsearchpath
    if resource[:active].eql?(:true)
      return false unless @searchpath.member?(@our_node)
    else
      return false if @searchpath.member?(@our_node)
    end
    return false unless File.exists?(@parent)
    stat = File::Stat.new(@parent)
    return false unless stat.mode.eql?(DIRMODE)
    CHILD_DIRS.each do |child|
       return false unless File.exists?("#{@parent}/#{child}")
       return false unless File::Stat.new("#{@parent}/#{child}").mode.eql?(DIRMODE)
    end
    return cspsearchpath_active?
  end
  
  # Are we actively using the CSPSearchPath?
  def cspsearchpath_active?
    result = `dscl /Search -read / SearchPolicy 2> /dev/null`.chomp.split(": ")[1]
    result.eql?(SP_CUSTOM)
  end
  
  # Sets SearchPolicy to Local or Custom
  def set_searchpolicy(policy)
    the_cmd = "/usr/bin/dscl /Search -create / SearchPolicy #{policy} 2> /dev/null"
    system("#{the_cmd}")
    return $?.success?
  end
    
  # Creates a new CSPSearchPath
  def set_cspsearchpath(path)
    path = path.collect { |x| "\"#{x}\"" }.join(" ")
    the_cmd = "/usr/bin/dscl /Search -create / CSPSearchPath #{path} 2> /dev/null"
    system("#{the_cmd}")
    return $?.success?
  end
    
  # Returns CSPSearchPath as NSArray
  def get_cspsearchpath
    string = `dscl -plist /Search -read / CSPSearchPath 2> /dev/null`.to_ns
    return false if string.empty? or string.nil?
    data = string.dataUsingEncoding(NSUTF8StringEncoding)
    dict = NSPropertyListSerialization.objc_send(
      :propertyListFromData, data,
      :mutabilityOption, NSPropertyListMutableContainersAndLeaves,
      :format, nil,
      :errorDescription, nil
    )
    return false if dict.nil?
    dict['dsAttrTypeStandard:CSPSearchPath']
  end
  
  def restart_directoryservices(wait)
    this_operatingsystem_major_version = Facter.value(:macosx_productversion_major).to_f
    if this_operatingsystem_major_version <= 10.6
      system("killall DirectoryService")
    else
      system("killall opendirectoryd")
    end
    sleep wait
  end
  
  def statcheck(target)
    #not implemented
  end
    
end
