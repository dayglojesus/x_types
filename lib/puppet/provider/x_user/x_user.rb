begin
  require 'osx/cocoa'
  include OSX
rescue LoadError
  puts "This is not the operating system of my people! Let my people go!"
end

# Provider: dslocal_user
Puppet::Type.type(:x_user).provide(:x_user) do
  desc "Provides dscl interface for managing Mac OS X DSLocal users."

  commands  :dsclcmd          => "/usr/bin/dscl"
  commands  :uuidgen          => "/usr/bin/uuidgen"
  confine   :operatingsystem  => :darwin

  Req_Attrib_Map_User = { 'dsAttrTypeStandard:RecordName' => :name,
    'dsAttrTypeStandard:RealName'         => :name,
    'dsAttrTypeStandard:UniqueID'         => :uid,
    'dsAttrTypeStandard:PrimaryGroupID'   => :gid,
    'dsAttrTypeStandard:UserShell'        => :shell,
    'dsAttrTypeStandard:NFSHomeDirectory' => :home,
    'dsAttrTypeStandard:Comment'          => :comment
  }

  @@password_hash_dir = '/var/db/shadow/hash'
  
  def create
    info("Creating user account: #{resource[:name]}")
    unless @user.nil?  
       FileUtils.rm_rf(@file)
    end
    dsclcmd "/Local/#{resource[:dslocal_node]}", "-create", "/Users/#{resource[:name]}"
    Req_Attrib_Map_User.each do |key,value|
      dsclcmd "/Local/#{resource[:dslocal_node]}", "-create", "/Users/#{resource[:name]}", "#{key}", "#{resource[Req_Attrib_Map_User[key]]}"
    end
    # HUP the DS
    restart_directory_services
    # Flush the pending writes to disk
    system("sync")
    # Reload the user
    @user = get_user(resource[:name])
    unless @user.nil?
       set_password(@user)
    else
      fail("Could not load the user data file.")
    end
  end  

  def destroy
    begin
      info("Destroying user account: #{resource[:name]}")
      if @kernel_version_major < 11
        guid = @user['generateduid'][0].to_ruby
        password_hash_file = "#{@@password_hash_dir}/#{guid}"
        FileUtils.rm_rf(password_hash_file)
      end
      dsclcmd "/Local/#{resource[:dslocal_node]}", "-delete", "/Users/#{resource[:name]}"
    rescue Puppet::ExecutionFailure => detail
      fail("Could not destroy the user account #{resource[:name]}: #{detail}")
    end
  end

  def exists?
    @kernel_version_major = Facter.kernelmajversion.to_i
    # Load the user data
    @user = get_user(resource[:name])
    # Check the user data, if it's not there, jump to create
    info("Checking user account: #{resource[:name]}")
    if not @user.nil?
      # Roll through each user attribute to ensure it conforms
      Req_Attrib_Map_User.each do |key,value|
        return false unless @user[value].to_ruby.to_s.eql?(resource[value])
      end
      # Finally, check the password
      return password_match?
    else
      return false
    end
  end

  # Load the user data
  ## Returns an NSDictionary representation of the the user.plist if it exists
  ## If it doesn't, it will return nil
  def get_user(name)
    @file = "/private/var/db/dslocal/nodes//#{resource[:dslocal_node]}/users/#{name}.plist"
    user = NSMutableDictionary.dictionaryWithContentsOfFile(@file)
  end
  
  # Returns a bool
  def password_match?
    if @kernel_version_major >= 11
      get_hash_sha512(@user).eql?(resource[:password_sha512])
    else
      get_hash_sha1(@user).eql?(resource[:password_sha1])
    end
  end
  
  # Restart Directory Services
  ## Yes, that's all it does
  def restart_directory_services
    if @kernel_version_major >= 11
      system("killall opendirectoryd")
    else
      system("killall DirectoryService")
    end
    sleep 2
  end
    
  
  # Parses the shadow hash file on disk; returns Ruby String
  ## Stolen and modified from Puppet core
  def get_hash_sha1(user)
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
  end
  
  # Expects an NSDictionary; returns Ruby String
  def get_hash_sha512(user)
    shadowhashdata = user['ShadowHashData'][0]
    # The ShadowHashData key is actually an embedded Binary plist
    # We Serialize this into a new NSDictionary
    @embedded_bplist = NSPropertyListSerialization.objc_send(
      :propertyListFromData, shadowhashdata,
      :mutabilityOption, NSPropertyListMutableContainersAndLeaves,
      :format, nil,
      :errorDescription, nil
    )
    # Returns NSMutableData object containing Hexadecimal ASCII String 
    # This is the Salt + the actual SHA512 hash
    # We make it an array, and strip the angle brackets (how do you do this without gsub? Is there a Objc method?)
    hash = @embedded_bplist['SALTED-SHA512'].to_s.gsub(/<|>/,"").split
    # Desalinate: Lop off the first 4 bytes which is just the salt
    # sugar = hash.shift
    hash.join
  end
  
  # Set Lion Passwords
  ## Fix the authentication_authority
  ## Read hash from attribs, re-format it, serialize it, 
  ## Now, write the whole user plist to disk 
  def set_password_sha512(user)
    aa = fix_authentication_authority(user)
    user['authentication_authority'] = aa
    salted_hash_hex = resource[:password_sha512]
    string = convert_hex_to_ascii(salted_hash_hex)
    data = NSData.alloc.initWithBytes_length_(string, string.length)
    @embedded_bplist = NSMutableDictionary.new if @embedded_bplist.nil?
    @embedded_bplist['SALTED-SHA512'] = data
    user['ShadowHashData'][0] = NSPropertyListSerialization.objc_send(
      :dataFromPropertyList, @embedded_bplist,
      :format, NSPropertyListBinaryFormat_v1_0,
      :errorDescription, nil
    )
    result = user.writeToFile_atomically_(@file, true)
    raise("Could not write user plist to file: writeToFile_atomically_ returned nil") if result.nil?
    result
  end
  
  # Set Legacy Passwords
  ## Fix the authentication_authority
  ## Read hash from attribs, and write it to disk as a shadow hash
  ## Now, write the whole user plist to disk 
  ## Mostly stolen from Puppet core and modified
  def set_password_sha1(user)
    aa = fix_authentication_authority(user)
    user['authentication_authority'] = aa
    guid = user['generateduid'][0].to_ruby
    password_hash_file = "#{@@password_hash_dir}/#{guid}"
    begin
      File.open(password_hash_file, 'w') { |f| f.write(resource[:password_sha1])}
    rescue Errno::EACCES => detail
      raise("Could not write to password hash file: #{detail}")
    end
    result = user.writeToFile_atomically_(@file, true)
    raise("Could not write user plist to file: writeToFile_atomically_ returned nil") if result.nil?
    result
  end
  
  # Self-explanatory
  def convert_hex_to_ascii(string)
    string.scan(/../).collect { |byte| byte.hex.chr }.join
  end
  
  # Rebuild the AuthenticationAuthority
  ## Takes user dictionary as its arg
  ## Returns a new AuthenticationAuthority array
  ## Hopefully does nto destroy any other types of hashes
  def fix_authentication_authority(user)
    index = 0
    preamble = ';ShadowHash;HASHLIST:'
    hashlist = []
    authority = user['authentication_authority']
    unless authority.nil?
      index = authority.to_ruby.index { |e| e =~ /^;ShadowHash;/ }
      # We match and then use the post-match
      unless $'.empty? or $'.nil?
        hashlist = $'.split(":").pop                      # pop the real values off the HASHLIST: grab token and discard the rest
        hashlist = hashlist.gsub!(/<|>/,"").split(",")    # lose the angle brackets and populate an array with the comma sep. vals.
        hashlist.delete_if { |e| e =~ /SALTED-SHA/ }      # for economy, just purge the list of any SHA authorities
      end
    else
      authority = NSMutableArray.new
    end
    if @kernel_version_major >= 11
      hashlist << 'SALTED-SHA512'
    else
      hashlist << 'SALTED-SHA1'
    end
    authority[index] = preamble + "<#{hashlist.join(",")}>"
    authority
  end
    
  # Set the password
  ## Based on which OS we are operating on
  def set_password(user)
    begin
      if @kernel_version_major >= 11
        set_password_sha512(user)
      else
        set_password_sha1(user)
      end
    rescue Puppet::ExecutionFailure => detail
      fail("Could not set the password for #{resource[:name]}: #{detail}")
    end
  end

end
