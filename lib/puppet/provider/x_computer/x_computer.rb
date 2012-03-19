# Provider: x_computer
# Created: Mon Dec  5 12:19:52 PST 2011

begin
  require 'pp'
  require 'osx/cocoa'
  include OSX
rescue LoadError
  puts "What are you doing, Dave? This is highly irregular."
end

Puppet::Type.type(:x_computer).provide(:x_computer) do
  desc "Provides dscl interface for managing Mac OS X computers."

  commands  :dsclcmd          => "/usr/bin/dscl"
  commands  :uuidgen          => "/usr/bin/uuidgen"
  confine   :operatingsystem  => :darwin

  Req_Attrib_Map_Computer = { 'dsAttrTypeStandard:RecordName' => :name,
    'dsAttrTypeStandard:RealName'     => :name,
    'dsAttrTypeStandard:ENetAddress'  => :en_address,
    'dsAttrTypeStandard:HardwareUUID' => :hardware_uuid
  }

  def create
    info("Creating computer record: #{resource[:name]}")
    guid = uuidgen.chomp
    if @computer
      guid = @computer['dsAttrTypeStandard:GeneratedUID'].to_s
      raise if guid.nil? or guid.empty?
      @needs_repair.each do |attrib|
        dsclcmd "/Local/#{resource[:dslocal_node]}", "-merge", "/Computers/#{resource[:name]}", "#{attrib}", "#{resource[Req_Attrib_Map_Computer[attrib]]}"
      end
    else
      dsclcmd "/Local/#{resource[:dslocal_node]}", "-create", "/Computers/#{resource[:name]}"
      Req_Attrib_Map_Computer.each do |key,value|
        dsclcmd "/Local/#{resource[:dslocal_node]}", "-merge", "/Computers/#{resource[:name]}", "#{key}", "#{resource[Req_Attrib_Map_Computer[key]]}"
      end
    end
  end

  def destroy
    info("Destroying computer record: #{resource[:name]}")
    dsclcmd "/Local/#{resource[:dslocal_node]}", "-delete", "/Computers/#{resource[:name]}"
  end

  def exists?
    info("Checking computer record: #{resource[:name]}")
    # Leopard does nto allow HardwareUUID computer record attribute 
    @kernel_version_major = Facter.kernelmajversion.to_i
    Req_Attrib_Map_Computer.delete('dsAttrTypeStandard:HardwareUUID') if @kernel_version_major == 9
    @needs_repair = []
    @computer = get_computer(resource[:name])
    if @computer
      Req_Attrib_Map_Computer.each do |key,value|
        @needs_repair << key unless @computer[key].to_s.eql?(resource[value])
      end
      return false unless @needs_repair.empty?
    else
      return false
    end
    true
  end

  # Returns a hash of computer properties
  def get_computer(name)
    string = `dscl -plist /Local/#{resource[:dslocal_node]} -read /Computers/#{name} 2> /dev/null`.to_ns
    return false if string.empty? or string.nil?
    data = string.dataUsingEncoding(OSX::NSUTF8StringEncoding)
    dict = OSX::NSPropertyListSerialization.objc_send(
      :propertyListFromData, data,
      :mutabilityOption, OSX::NSPropertyListMutableContainersAndLeaves,
      :format, nil,
      :errorDescription, nil
    )
    return false if dict.nil?
    dict.to_ruby
  end

end
