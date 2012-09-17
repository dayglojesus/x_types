# Provider: x_computer
# Created: Mon Dec  5 12:19:52 PST 2011

begin
  require 'osx/cocoa'
  include OSX
rescue LoadError
  puts "What are you doing, Dave? This is highly irregular."
end

Puppet::Type.type(:x_computer).provide(:x_computer) do
  desc "Provides RubyCocoa interface for managing Mac OS X computer records with Puppet."

  confine     :operatingsystem => :darwin
  defaultfor  :operatingsystem => :darwin

  @@required_attributes_computer = [ :name, :realname, :en_address, :hardware_uuid ]

  def create
    freshie = @computer.empty?
    info("Creating computer record: #{resource[:name]}")
    @@required_attributes_computer.each do |attrib|
      # info("create: adding #{attrib} attribute, #{resource[attrib]}")
      @computer[attrib.to_s] = [ resource[attrib] ]
    end
    @computer['generateduid'] = [ new_generateduid ] unless @computer['generateduid']
    result = @computer.writeToFile_atomically_(@file, true)
    raise("Could not write computer plist to file: writeToFile_atomically_ returned nil") if result.nil?
    # restart_directoryservices(11) if freshie
    result
  end

  def destroy
    info("Destroying computer record: #{resource[:name]}")
    delete_computer
  end

  def exists?
    @kernel_version_major = Facter.kernelmajversion.to_i
    @computer = get_computer(resource[:name]) || NSMutableDictionary.new
    @@required_attributes_computer.delete(:hardware_uuid) if @kernel_version_major == 9
    info("Checking computer record: #{resource[:name]}")
    if not @computer.empty?
      begin
        return false unless @computer['generateduid']
        # Roll through each required user attribute to ensure it conforms
        @@required_attributes_computer.each do |attrib|
          unless @computer[attrib.to_s].to_ruby.to_s.eql?(resource[attrib])
            # info("Attrib: #{attrib}, does not match")
            return false
          end
        end
      rescue
        info("There was an unspecified error while parsing the computer plist.")
        return false
      end
    else
      # info("No such record: #{resource[:name]}")
      return false
    end
  end

  # Return a new generateduid
  def new_generateduid
    CFUUIDCreateString(nil, CFUUIDCreate(nil))
  end

  # Load the computer object
  ## Returns an NSDictionary representation of the the user.plist if it exists
  ## If it doesn't, it will return nil
  def get_computer(name)
    @file = "/private/var/db/dslocal/nodes//#{resource[:dslocal_node]}/computers/#{name}.plist"
    NSMutableDictionary.dictionaryWithContentsOfFile(@file)
  end

  # Delete the user and applicable shadow hash file
  def delete_computer
    begin
      FileUtils.rm_rf(@file)
    rescue Puppet::ExecutionFailure => detail
      fail("Could not destroy the computer record, #{resource[:name]}: #{detail}")
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
