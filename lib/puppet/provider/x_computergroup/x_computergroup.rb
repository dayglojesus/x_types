# Provider: x_computergroup
# Created: Mon Nov 28 10:38:36 PST 2011

begin
  require 'pp'
  require 'osx/cocoa'
  include OSX
rescue LoadError
  puts "Does not compute. Does not compute. Does not compute."
end

Puppet::Type.type(:x_computergroup).provide(:x_computergroup) do
  desc "Provides dscl interface for managing Mac OS X computer groups."

  commands  :dsclcmd          => "/usr/bin/dscl"
  commands  :uuidgen          => "/usr/bin/uuidgen"
  confine   :operatingsystem  => :darwin

  @@req_attrib_map_computergroup = { 
    'name'      => :name,
    'realname'  => :name,
    'gid'       => :gid,
  }

  def create    
    # Fix the existing record or create it as required
    if @computergroup
      info("Repairing computer group: #{resource[:name]}")
      guid = @computergroup['generateduid'].to_s
      raise if guid.nil? or guid.empty?
      unless @needs_repair.empty? or @needs_repair.nil?
        @needs_repair.each do |attrib|
          dsclcmd "/Local/#{resource[:dslocal_node]}", "-create", "/ComputerGroups/#{resource[:name]}", "#{attrib}", "#{resource[@@req_attrib_map_computergroup[attrib]]}"
        end
      end
    else
      info("Creating computer group: #{resource[:name]}")
      dsclcmd "/Local/#{resource[:dslocal_node]}", "-create", "/ComputerGroups/#{resource[:name]}"
      @@req_attrib_map_computergroup.each do |key,value|
        dsclcmd "/Local/#{resource[:dslocal_node]}", "-create", "/ComputerGroups/#{resource[:name]}", "#{key}", "#{resource[@@req_attrib_map_computergroup[key]]}"
      end
    end
    # Populate the group membership
    unless resource[:computers].empty? or resource[:computers].nil?
      operation = '-merge'
      operation = '-create' if resource[:autocratic]
      @computers_by_guid.each do |key, value|
        dsclcmd "/Local/#{resource[:dslocal_node]}", "#{operation}", "/ComputerGroups/#{resource[:name]}", "GroupMembers", "#{key}"
        dsclcmd "/Local/#{resource[:dslocal_node]}", "#{operation}", "/ComputerGroups/#{resource[:name]}", "GroupMembership", "#{value}"
      end
    end
  end

  def destroy
    info("Destroying computer group: #{resource[:name]}")
    dsclcmd "/Local/#{resource[:dslocal_node]}", "-delete", "/ComputerGroups/#{resource[:name]}"
  end

  def exists?
    info("Checking computer group: #{resource[:name]}")
    @needs_repair = []
    unless resource[:computers].empty? or resource[:computers].nil?
      @computers_by_guid = get_computer_guids_by_name(resource[:computers])
    end
    begin
      @computergroup = get_computergroup(resource[:name]).to_ruby
      if @computergroup
        @@req_attrib_map_computergroup.each do |key,value|
          @needs_repair << key unless @computergroup[key].to_s.eql?(resource[value])
        end
        return unless check_computers?(@computers_by_guid)
      else
        return false
      end
    rescue
      return false
    end
    return @needs_repair.empty?
  end

  # Check the resource defined membership against the real membership
  # Returns boolean
  def check_computers?(map)
    return false if @computergroup['groupmembers'].nil? or @computergroup['users'].nil?
    unless map.nil? or map.empty?
      begin
        return false unless @computergroup['groupmembers'].sort.eql?(map.keys.sort)
        return false unless @computergroup['users'].sort.eql?(map.values.sort)
      rescue
        return false
      end
    end
    true
  end

  # Returns a hash mapping GUID to computername
  def get_computer_guids_by_name(names)
    members_by_guid = {}
    names.each do |member|
      begin
        member_guid = (`dscl /Local/#{resource[:dslocal_node]} -read /Computers/#{member} GeneratedUID 2> /dev/null`.split(": ")[1]).chomp
        members_by_guid[member_guid] = member
      rescue
        notice("Attempt to retrieve GUID for record #{member} returned: #{$?.exitstatus} -- Record not found. Cannot add member \"#{member}\" to computer group: #{resource[:name]}")
        warn("Attempt to retrieve GUID for record #{member} returned: #{$?.exitstatus} -- Record not found. Cannot add member \"#{member}\" to computer group: #{resource[:name]}")
      end
    end
    members_by_guid
  end

  # Load the computergroup data
  ## Returns an NSDictionary representation of the the computergroup.plist if it exists
  ## If it doesn't, it will return nil
  def get_computergroup(name)
    @file = "/private/var/db/dslocal/nodes//#{resource[:dslocal_node]}/computergroups/#{name}.plist"
    computergroup = NSMutableDictionary.dictionaryWithContentsOfFile(@file)
  end

end
