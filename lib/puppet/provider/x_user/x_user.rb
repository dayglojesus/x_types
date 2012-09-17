# Provider: x_user
# Created: Mon Dec  5 12:19:52 PST 2011

begin
  require 'osx/cocoa'
  include OSX
rescue LoadError
  puts "This is not the operating system of my people! Let my people go!"
end

Puppet::Type.type(:x_user).provide(:x_user) do
  desc "Provides RubyCocoa interface for managing Mac OS X local users."

  confine     :operatingsystem => :darwin
  defaultfor  :operatingsystem => :darwin

  @@required_attributes = [ :name, :realname, :uid, :gid, :shell, :home, :comment ]
  @@password_hash_dir = '/var/db/shadow/hash'
  
  def create
    freshie = true
    unless @user.empty?
      freshie = false
      delete_user
    end
    info("Creating user account: #{resource[:name]}")
    @@required_attributes.each do |attrib|
      # info("create: adding #{attrib} attribute, #{resource[attrib]}")
      @user[attrib.to_s] = [ resource[attrib] ]
    end
    set_password
    set_authentication_authority unless @user['authentication_authority']
    # Write the changes to disk; ALL the changes
    result = @user.writeToFile_atomically_(@file, true)
    raise("Could not write user plist to file: writeToFile_atomically_ returned nil") if result.nil?
    restart_directoryservices(11) if freshie
    result
  end
  
  def destroy
    info("Destroying user account: #{resource[:name]}")
    delete_user
  end
  
  def exists?
    @kernel_version_major = Facter.kernelmajversion.to_i
    # Load the user data
    @user = get_user(resource[:name]) || NSMutableDictionary.new
    # Check the user data, if it's not there, jump to create
    info("Checking user account: #{resource[:name]}")
    if not @user.empty?
      begin
        # Roll through each required user attribute to ensure it conforms
        @@required_attributes.each do |attrib|
          unless @user[attrib.to_s].to_ruby.to_s.eql?(resource[attrib])
            # info("Attrib: #{attrib}, does not match")
            return false
          end
        end
      rescue
        info("There was an unspecified error while parsing the user plist.")
        return false
      end
      return false unless @user['authentication_authority']
      # Finally, check the password
      return password_match?
    else
      # info("No such account: #{resource[:name]}")
      return false
    end
  end
  
  # Load the user data
  ## Returns an NSDictionary representation of the the user.plist if it exists
  ## If it doesn't, it will return nil
  def get_user(name)
    @file = "/private/var/db/dslocal/nodes//#{resource[:dslocal_node]}/users/#{name}.plist"
    NSMutableDictionary.dictionaryWithContentsOfFile(@file)
  end
  
  # Returns a bool
  def password_match?
    if @kernel_version_major == 12
      get_hash_sha512_pbkdf2(@user).eql?(resource[:password_sha512_pbkdf2])
    elsif @kernel_version_major == 11
      get_hash_sha512(@user).eql?(resource[:password_sha512])
    else
      get_hash_sha1(@user).eql?(resource[:password_sha1])
    end
  end
  
  # Parses the shadow hash file on disk; returns Ruby String
  ## Stolen and modified from Puppet core
  def get_hash_sha1(user)
    begin
      guid = user['generateduid'][0].to_ruby
      password_hash = nil
      password_hash_file = "#{@@password_hash_dir}/#{guid}"
      if File.exists?(password_hash_file) and File.file?(password_hash_file)
        fail("Could not read password hash file at #{password_hash_file}") if not File.readable?(password_hash_file)
        f = File.new(password_hash_file)
        password_hash = f.read
        f.close
      end
      password_hash
    rescue
      return String,new
    end
  end
  
  # Expects an NSDictionary; returns Ruby String
  def get_hash_sha512(user)
    begin
      shadowhashdata = user['ShadowHashData'][0]
      embedded_bplist = NSPropertyListSerialization.objc_send(
        :propertyListFromData, shadowhashdata,
        :mutabilityOption, NSPropertyListMutableContainersAndLeaves,
        :format, nil,
        :errorDescription, nil
      )
      hash = embedded_bplist['SALTED-SHA512'].to_s.gsub(/<|>/,"").split
      hash.join
    rescue
      return String.new
    end
  end
  
  # Expects an NSDictionary; returns Ruby Hash
  def get_hash_sha512_pbkdf2(user)
    begin
      shadowhashdata = user['ShadowHashData'][0]
      embedded_bplist = NSPropertyListSerialization.objc_send(
        :propertyListFromData, shadowhashdata,
        :mutabilityOption, NSPropertyListMutableContainersAndLeaves,
        :format, nil,
        :errorDescription, nil
      )
      plist = embedded_bplist.values[0].to_ruby
      resource = {}
      resource['iterations'] = plist['iterations'].to_s
      resource['salt'] = plist['salt'].description.to_ruby.gsub!(/<|>/,"").split.join
      resource['entropy'] = plist['entropy'].description.to_ruby.gsub!(/<|>/,"").split.join
      resource
    rescue
      return Hash.new
    end
  end
  
  # Returns a ShadowHashData structure (NSData)
  # - label is s string representing type of hash being stored
  # - data is the NSDictionary object you want stored
  def create_shadowhashdata(label, data)
    plist = NSMutableDictionary.new
    plist[label] = data
    NSPropertyListSerialization.objc_send(
      :dataFromPropertyList, plist,
      :format, NSPropertyListBinaryFormat_v1_0,
      :errorDescription, nil
    )
  end
  
  # Self-explanatory
  def convert_hex_to_ascii(string)
    string.scan(/../).collect { |byte| byte.hex.chr }.join
  end
  
  # Encode a hexidecimal string as NSData
  def encode_hex_to_nsdata(hex)
    ascii = convert_hex_to_ascii(hex)
    data = NSData.alloc.initWithBytes_length_(ascii, ascii.length)    
  end
  
  # Set the password
  def set_password
    begin
      if @kernel_version_major == 12
        set_password_mtnlion(resource[:password_sha512_pbkdf2])
      elsif @kernel_version_major == 11
        set_password_lion(resource[:password_sha512])
      else
        set_password_legacy
      end
    rescue Puppet::ExecutionFailure => detail
      fail("Could not set the password for #{resource[:name]}: #{detail}")
    end
  end
  
  # Create a ShadowHashData attribute for the user
  def set_password_mtnlion(hash)
    data = NSMutableDictionary.new
    data['entropy'] = encode_hex_to_nsdata(hash['entropy'])
    data['salt'] = encode_hex_to_nsdata(hash['salt'])
    data['iterations'] = hash['iterations'].to_i
    @user['ShadowHashData'] = NSMutableArray.new
    @user['ShadowHashData'][0] = create_shadowhashdata('SALTED-SHA512-PBKDF2', data)
  end

  # Create a ShadowHashData attribute for the user
  def set_password_lion(hash)
    salted_hash_hex = hash
    string = convert_hex_to_ascii(salted_hash_hex)
    data = NSData.alloc.initWithBytes_length_(string, string.length)
    @user['ShadowHashData'] = NSMutableArray.new
    @user['ShadowHashData'][0] = create_shadowhashdata('SALTED-SHA512', data)
  end
  
  # Create a shadow has file for the user
  def set_password_legacy
    if @user['generateduid']
      guid = @user['generateduid'][0].to_ruby
    else
      guid = new_generateduid.to_ruby
    end
    @user['generateduid'] = [ guid ]
    password_hash_file = "#{@@password_hash_dir}/#{guid}"
    begin
      File.open(password_hash_file, 'w') { |f| f.write(resource[:password_sha1])}
    rescue Errno::EACCES => detail
      raise("Could not write to password hash file: #{detail}")
    end
  end
  
  # Set the authentication authority
  def set_authentication_authority
    value = ';ShadowHash;HASHLIST:'
    authority = NSMutableArray.new      
    if @kernel_version_major == 12
      value << '<SALTED-SHA512-PBKDF2>'
    elsif @kernel_version_major == 11
      value << '<SALTED-SHA512>'
    else
      value << '<SALTED-SHA1>'
    end
    authority << value
    @user['authentication_authority'] = authority
  end
  
  # Return a new generateduid
  def new_generateduid
    CFUUIDCreateString(nil, CFUUIDCreate(nil))
  end
  
  # Delete the user and applicable shadow hash file
  def delete_user
    begin
      if @kernel_version_major < 11
        guid = @user['generateduid'][0].to_ruby
        password_hash_file = "#{@@password_hash_dir}/#{guid}"
        FileUtils.rm_rf(password_hash_file)
      end
      FileUtils.rm_rf(@file)
    rescue Puppet::ExecutionFailure => detail
      fail("Could not destroy the user account #{resource[:name]}: #{detail}")
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
