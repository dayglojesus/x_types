# Provider: x_computergroup
# Created: Mon Nov 28 10:38:36 PST 2011

begin
  require 'osx/cocoa'
  include OSX
rescue LoadError
  puts "Does not compute. Does not compute. Does not compute."
end

Puppet::Type.type(:x_computergroup).provide(:x_computergroup) do
  desc "Provides RubyCocoa interface for managing Mac OS X computergroup records with Puppet."

  confine     :operatingsystem => :darwin
  defaultfor  :operatingsystem => :darwin

  @@required_attributes_computergroup = [ :name, :realname, :gid ]

  def create
    freshie = @computergroup.empty?
    info("Creating computergroup record: #{resource[:name]}")
    @@required_attributes_computergroup.each do |attrib|
      # info("create: adding #{attrib} attribute, #{resource[attrib]}")
      @computergroup[attrib.to_s] = [ resource[attrib] ]
    end
    @computergroup['generateduid'] = [ new_generateduid ] unless @computergroup['generateduid']
    add_computer_members
    result = @computergroup.writeToFile_atomically_(@file, true)
    raise("Could not write computergroup plist to file: writeToFile_atomically_ returned nil") if result.nil?
    restart_directoryservices(11) if freshie
    result
  end

  def destroy
    info("Destroying computer group: #{resource[:name]}")
    delete_computergroup
  end

  def exists?
    @kernel_version_major = Facter.kernelmajversion.to_i
    @computergroup = get_computergroup(resource[:name]) || NSMutableDictionary.new
    info("Checking computer group: #{resource[:name]}")
    if not @computergroup.empty?
      begin
        # Roll through each required user attribute to ensure it conforms
        @@required_attributes_computergroup.each do |attrib|
          unless @computergroup[attrib.to_s].to_ruby.to_s.eql?(resource[attrib])
            # info("Attrib: #{attrib}, does not match")
            return false
          end
        end
        # Check membership
        unless resource[:computers].empty? or resource[:computers].nil?
          return check_computer_membership
        end
      rescue => error
        # puts error.message
        info("There was an unspecified error while parsing the computergroup plist.")
        return false
      end
    else
      # info("No such account: #{resource[:name]}")
      return false
    end
  end
  
  # Load the computergroup object
  ## Returns an NSDictionary representation of the the computergroup.plist if it exists
  ## If it doesn't, it will return nil
  def get_computergroup(name)
    @file = "/private/var/db/dslocal/nodes/#{resource[:dslocal_node]}/computergroups/#{name}.plist"
    NSMutableDictionary.dictionaryWithContentsOfFile(@file)
  end
  
  # Delete the user and applicable shadow hash file
  def delete_computergroup
    begin
      FileUtils.rm_rf(@file)
    rescue Puppet::ExecutionFailure => detail
      fail("Could not destroy the computergroup record, #{resource[:name]}: #{detail}")
    end
  end
  
  # Return a new generateduid
  def new_generateduid
    CFUUIDCreateString(nil, CFUUIDCreate(nil))
  end
  
  def check_computer_membership
    current_members  = @computergroup['users'].to_ruby || []
    assigned_members = resource[:computers].to_a || []
    if resource[:autocratic].to_s =~ /true|enable/
      return current_members.sort.eql?(assigned_members.sort)
    else
      composite = assigned_members & current_members
      return composite.sort.eql?(assigned_members.sort)
    end
  end

  def add_computer_members
    map = {}
    assigned_members = resource[:computers].to_a || []
    assigned_members.each do |member|
      path = "/private/var/db/dslocal/nodes/MCX/computers/#{member}.plist"
      if File.exists?(path)        
        record = NSMutableDictionary.dictionaryWithContentsOfFile(path)
        key = record['generateduid'].to_ruby.to_s
        map[key] = member
      else
        fail("Could not add computer member, \'#{member}\': no such record")
      end
    end
    if resource[:autocratic].to_s =~ /true|enable/
      @computergroup['groupmembers'] = map.keys.to_ns
      @computergroup['users'] = map.values.to_ns
    else
      @computergroup['groupmembers'] = @computergroup['groupmembers'] || map.keys.to_ns
      @computergroup['users'] = @computergroup['users'] || map.values.to_ns
    end
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
