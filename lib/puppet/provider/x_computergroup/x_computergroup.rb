# Provider: x_computergroup
# Created: Mon Nov 28 10:38:36 PST 2011, bcw@sfu.ca
# TODO
# - better error checking on dscl cmds, especially computernames
Puppet::Type.type(:x_computergroup).provide(:x_computergroup) do
  desc "Provides dscl interface for managing Mac OS X computer groups."

  commands  :dsclcmd          => "/usr/bin/dscl"
  commands  :uuidgen          => "/usr/bin/uuidgen"
  confine   :operatingsystem  => :darwin

  def create
    info("Creating computer group: #{resource[:name]}")
    # Generate a GUID for the computer group
    group_guid = uuidgen.chomp
    # Delete the group first
    dsclcmd "/Local/#{resource[:dslocal_node]}", "-delete", "/ComputerGroups/#{resource[:name]}" if get_computergroup(resource[:name])
    # Re-create it
    dsclcmd "/Local/#{resource[:dslocal_node]}", "-create", "/ComputerGroups/#{resource[:name]}"
    dsclcmd "/Local/#{resource[:dslocal_node]}", "-append",  "/ComputerGroups/#{resource[:name]}", "RealName", "#{resource[:name]}"
    dsclcmd "/Local/#{resource[:dslocal_node]}", "-append",  "/ComputerGroups/#{resource[:name]}", "PrimaryGroupID", "#{resource[:gid]}"
    dsclcmd "/Local/#{resource[:dslocal_node]}", "-append",  "/ComputerGroups/#{resource[:name]}", "GeneratedUID", "#{group_guid}"
    # Compile members
    unless resource[:members].empty? or resource[:members].nil?
      members_by_guid = get_computers_by_guids(resource[:members])
      members_by_guid.each do |key, value|
        dsclcmd "/Local/#{resource[:dslocal_node]}", "-append", "/ComputerGroups/#{resource[:name]}", "GroupMembers", "#{key}"
        dsclcmd "/Local/#{resource[:dslocal_node]}", "-append", "/ComputerGroups/#{resource[:name]}", "GroupMembership", "#{value}"
      end
    end
  end

  def destroy
    info("Destroying computer group: #{resource[:name]}")
    dsclcmd "/Local/#{resource[:dslocal_node]}", "-delete", "/ComputerGroups/#{resource[:name]}"
  end

  def exists?
    info("Checking computer group: #{resource[:name]}")
    if computer_group = get_computergroup(resource[:name])
      required_attribs = ['RecordName','RealName','PrimaryGroupID']
      required_attribs.each do |attrib|
        actual = (`dscl /Local/#{resource[:dslocal_node]} -read /ComputerGroups/#{resource[:name]} #{attrib} 2> /dev/null`).chomp.gsub!(/#{attrib}: /,"")
        return false if actual.nil? or actual.empty?
        return false unless computer_group["#{attrib}"].eql?(actual)
      end
      unless resource[:members].empty? or resource[:members].nil?
        return false if computer_group["GroupMembers"].nil? or computer_group["GroupMembership"].nil?
        members_by_guid = get_computers_by_guids(resource[:members])
        return false unless computer_group.delete("GroupMembers").split.sort.eql?(members_by_guid.keys.sort)
        return false unless computer_group.delete("GroupMembership").split.sort.eql?(members_by_guid.values.sort)
      end
    else
      return false
    end
    true
  end
  
  # Returns a hash of computergroup properties
  def get_computergroup(name)
    result = `dscl /Local/#{resource[:dslocal_node]} -read /ComputerGroups/#{name} 2> /dev/null`.split("\n").collect(&:chomp)
    return false if result.empty? or result.nil?
    computer_group = {}
    result.each do |x|
      key, value = x.split(": ")
      computer_group[key] = value
    end
    computer_group
  end
  
  # Returns a hash mapping GUID to computername
  def get_computers_by_guids(names)
    members_by_guid = {}
    names.each do |member|
      member_guid = (`dscl /Local/#{resource[:dslocal_node]} read /Computers/#{member} GeneratedUID 2> /dev/null`.split(": ")[1]).chomp
      members_by_guid[member_guid] = member
    end
    members_by_guid
  end
  
end

