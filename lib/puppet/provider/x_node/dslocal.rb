# Provider: dslocal
# Created: Tue Oct 16 13:17:23 PDT 2012

begin
  require 'fileutils'
  require 'osx/cocoa'
  include OSX
rescue LoadError
  puts "Move along, nothing to see here."
end

Puppet::Type.type(:x_node).provide(:dslocal) do
  desc 'Provides RubyCocoa interface for managing Mac OS X DSLocal nodes.'

  confine :operatingsystem => :darwin
  
  @@dslocal_root       = '/private/var/db/dslocal/nodes'
  @@child_dirs         = ['aliases', 'computer_lists', 'computergroups', 'computers', 'config', 'groups', 'networks', 'users']
  @@dirmode            = 16832
  @@filemode           = 33152
  @@preferences        = '/Library/Preferences/OpenDirectory/Configurations/Search.plist'
  @@preferences_legacy = '/Library/Preferences/DirectoryService/SearchNodeConfig.plist'
  
  def create
    info("Creating local node: #{resource[:name]}")
    # Create the dir structure for the local node
    create_directories
    # Add or remove the node as required
    if activate?
      @configuration.insert_node(@label) unless @configuration.cspsearchpath_has_node?(@label)
    else
      @configuration.remove_node(@label) if @configuration.cspsearchpath_has_node?(@label)
    end    
    @configuration.set_searchpolicy
    @configuration.writeToFile_atomically_(@file, true)
    restart_directoryservices(11)
  end

  def destroy
    info("Destroying local node: #{resource[:name]}")
    FileUtils.rm_rf(@parent) if File.exist?("#{@parent}")
    @configuration.remove_node(@label) if @configuration.cspsearchpath_has_node?(@label)
    @configuration.writeToFile_atomically_(@file, true)
    restart_directoryservices(11)
  end
  
  def exists?
    info("Checking local node: #{resource[:name]}")
    @label  = "/Local/#{resource[:name]}"
    @parent = "#{@@dslocal_root}/#{resource[:name]}"
    @configuration = load_configuration_file
    
    # This logic is really lame, but it's concise.
    if activate?
      return false unless @configuration.cspsearchpath_has_node?(@label)
    else
      return false if @configuration.cspsearchpath_has_node?(@label)
    end
    
    # Check directory structure
    return false unless File.exists?(@parent)
    stat = File::Stat.new(@parent)
    return false unless stat.mode.eql?(@@dirmode)
    @@child_dirs.each do |child|
       return false unless File.exists?("#{@parent}/#{child}")
       return false unless File::Stat.new("#{@parent}/#{child}").mode.eql?(@@dirmode)
    end
    
    # false unless we using a custom search policy
    return @configuration.searchpolicy_is_custom?
  end
  
  # Shoehorn methods into the NSMutableDictionary's singleton class
  # Add some instance vars which get evaluated at runtime (we get setter methods for free this way)
  def shoehorn(this)
    
    class << this
      
      attr_accessor :paths_key, :cspsearchpath, :policy_key, :searchpolicy, :custom
      
      # Returns the search paths array
      def cspsearchpath
        eval @paths_key
      end
      
      # Returns the search policy
      def searchpolicy
        eval @policy_key
      end
      
      # Insert the node
      # after any predefined local nodes, but before any network nodes
      def insert_node(node)
        dslocal_node  = '/Local/Default'
        bsd_node      = '/BSD/local'
        if index = cspsearchpath.index(bsd_node)
          cspsearchpath.insert(index + 1, node)
        elsif index = cspsearchpath.index(dslocal_node)
          cspsearchpath.insert(index + 1, node)
        else
          cspsearchpath.unshift(node)
        end
      end
      
      # Remove the node from the search path
      def remove_node(node)
        cspsearchpath.delete(node)
      end
      
      # Test whtehr or nt the ndoe is in the search path
      def cspsearchpath_has_node?(node)
        cspsearchpath.member?(node)
      end
      
      # Has custom ds searching been enabled?
      def searchpolicy_is_custom?
        value = searchpolicy.to_ruby
        value.eql?(@custom)
      end
      
      # Set the search opolicy to custom
      def set_searchpolicy
        searchpolicy = @custom
      end
      
    end
    
    # Set some instance vars at runtime
    # Values depend on the struture of the file we've opened
    this.paths_key  = %q{self['Search Node Custom Path Array']}
    this.policy_key = %q{self['Search Policy']}
    this.custom     = 3
    if this['modules']
      this.paths_key  = %q{self['modules']['session'][0]['options']['dsAttrTypeStandard:CSPSearchPath']}
      this.policy_key = %q{self['modules']['session'][0]['options']['dsAttrTypeStandard:SearchPolicy']}
      this.custom     = 'dsAttrTypeStandard:SearchPolicy'
    end      
    this
    
  end
  
  def activate?
    return true if resource[:active].eql? :true
    false
  end
    
  def create_directories
    begin
      FileUtils.mkdir_p("#{@parent}") unless File.exist?("#{@parent}")
      FileUtils.chmod(0700, "#{@parent}")
      @@child_dirs.each do |child|
        FileUtils.mkdir_p("#{@parent}/#{child}") unless File.exist?("#{@parent}/#{child}")
        FileUtils.chmod(0700, "#{@parent}/#{child}")
      end
      FileUtils.chown_R('root', 'wheel', "#{@parent}")
    rescue Exception => e  
      p e.message  
      # p e.backtrace.inspect
    end
  end
  
  def load_configuration_file
    @file = @@preferences_legacy
    @file = @@preferences if File.exists?(@@preferences)
    shoehorn(NSMutableDictionary.dictionaryWithContentsOfFile(@file))
  end
  
  def restart_directoryservices(wait)
    cmd = '/usr/bin/killall DirectoryService'
    cmd = '/usr/bin/killall opendirectoryd' if File.exists? '/usr/libexec/opendirectoryd'
    system cmd
    sleep wait
  end

end
