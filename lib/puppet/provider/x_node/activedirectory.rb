begin
  require 'rubygems'
  # require 'osx/cocoa'
  require 'resolv'
  require 'pp'
  require 'ping'
  # include OSX
rescue
  puts 'These are not the droids you are looking for...'
end

# Provider: activedirectory
# Created: Sat Mar  3 12:26:01 PST 2012, bcw@sfu.ca
Puppet::Type.type(:x_node).provide(:activedirectory) do
  
  desc 'Abstracts the dsconfiad utility and enables bind/unbind operations.'
  
  # command :dsconfigad       => '/usr/sbin/dsconfigad'
  confine :operatingsystem  => :darwin
  
  @@legacy_node_name    = '/Active Directory/All Domains'
  @@legacy_node_configs = [
    '/Library/Preferences/DirectoryService/SearchNodeConfig.plist', 
    '/Library/Preferences/DirectoryService/ContactsNodeConfig.plist'
  ]

  @@basic_options = [:username, :password, :computerid, :domain, :ou]
  @@dstype_params = [:ensure, :loglevel, :provider, :force, :active]
  @@adv_options   = [:protocol, :namespace, :groups, :ggid, :passinterval, :mobileconfirm, :preferred, 
    :localhome, :alldomains, :useuncpath, :packetsign, :uid, :packetencrypt, :gid, :authority, :shell, :mobile]
  
  @@legacy_config_file = '/Library/Preferences/DirectoryService/ActiveDirectory.plist'
  @@options_map = {
    # Basic properties
    :domain         => 'Active Directory Domain',
    :computerid     => 'Computer Account',
    # Advanced options
    :mobile         => 'Create mobile account at login',
    :mobileconfirm  => 'Require confirmation',
    :localhome      => 'Force home to startup disk',
    :useuncpath     => 'Use Windows UNC path for home',
    :protocol       => 'Network protocol to be used',
    :shell          => 'Default user Shell',
    :uid            => 'Mapping UID to attribute',
    :gid            => 'Mapping user GID to attribute',
    :ggid           => 'Mapping group GID to attribute',
    :preferred      => 'Preferred Domain controller',
    :groups         => 'Allowed admin groups',
    :alldomains     => 'Authentication from any domain',
    :packetsign     => 'Packet signing',
    :packetencrypt  => 'Packet encryption',
    :passinterval   => 'Password change interval',
    :namespace      => 'Namespace mode',
    :restrictddns   => 'Restrict Dynamic DNS updates',
  }
  
  def create    
    if domain_available?
      if ldap_available?  # BIND AND/OR CONFIG
        if @state
          configure
        else
          bind
          configure
        end
      else # ldap
        warn("No LDAP server available: [#{resource[:domain]}]")
        return true
      end # ldap
    else # domain
      warn("Active Directory domain unreachable: [#{resource[:domain]}]")
      return true
    end # domain
    true
  end
  
  def destroy
    notice("Removing node: #{resource[:domain]}")
    remove
    # true
  end
  
  def exists?
    notice("Checking network...")
    unless wait_for_network(30)
      notice("Network unavailable. We'll try again on the next run...")
      return true
    end
    notice("Checking state...")
    @state = false
    @kernel_version_major = Facter.kernelmajversion.to_i
    if @kernel_version_major < 11
      unless @legacy_config = load_legacy_config_file(@@legacy_config_file)
        fail("Could not load the legacy config file: #{@@legacy_config_file}")
      end
    end
    @options = options
    if already_bound?
      @state = true
      return check_options(@options)
    else
      notice("Machine is not bound to the domain...")
      check_options(@options)
      return false
    end
  end
  
  # Load a Mac OS X Property List
  def load_plist(path)
    plist = NSMutableDictionary.dictionaryWithContentsOfFile(path)
    debug("Property List file corrupt or non-existent.") if plist.nil?
    plist
  end

  # Load the a legacy DirectoryService config file
  # Try 3 times
  def load_legacy_config_file(file)
    count = 0
    legacy_config = load_plist(file)
    if legacy_config.nil?
      if count < 2
        system("dsconfigad -show &> /dev/null")
        restart_directoryservices(5)
        count += 1
        legacy_config = load_plist(file)
      else
        notice("Could not parse configuration file. Enable debugging for more info.")
        return true
      end
    end
    legacy_config
  end
    
  def check_options(options)
    notice("Checking plugin configuration...")
    @needs_repair = []
    @resource.parameters.keys.each do |p|
      # @@options_map is used as a mask to weed out params which we do not evaluate
      unless @@options_map[p].nil?
        current_state = options[@@options_map[p]].to_s
        desired_state = @resource.parameters[p].value.to_s
        unless current_state.eql?(desired_state)   
          @needs_repair << p 
        end
      end 
    end
    @@basic_options.each do |option|
      @needs_repair.delete(option)
    end
    @needs_repair.empty?
  end

  # Get AD plugin options
  def options
    result = {}
    `dsconfigad -show`.split("\n").each do |line|
      if line =~ /^Active Directory Domain|^Computer Account|^\s+/
        unless line =~ /None/i
          key, value = line.split("=")
          result[key.strip] = value.strip
        end
      end # end if
    end
    if @kernel_version_major < 10
      result['Namespace mode'] = get_legacy_namespace_value(@legacy_config)
      result['Password change interval'] = get_legacy_passinterval_value(@legacy_config)
    end
    process_options(result)
  end
  
  # Munge options into a usable form
  def process_options(options)
    inverted_map = @@options_map.invert
    options.each do |key, value|
      debug("Processing #{key}, #{key.class}")
      if (key =~ /^Mapping/) and (value =~ /not set/)
        options[key] = '-no' + @resource.parameters[inverted_map[key]].to_s
      elsif value =~ /Enabled|Disabled/
        options[key] = value.downcase.chop
      elsif key.eql?('Preferred Domain controller') and (value =~ /not set/)
        options['Preferred Domain controller'] = '-nopreferred'
      elsif key.eql?('Computer Account')
        options['Computer Account'].gsub!(/\$$/,'') # Strip dollar sign from end of name
      elsif key.eql?('Network protocol to be used')
        options['Network protocol to be used'].gsub!(/:$/,'') # Strip colon from end of protocol
      else
        debug("Option does not require processing.")
      end
    end
  end
    
  def get_legacy_passinterval_value(plist)
    result = plist['AD Advanced Options']['Password Change Interval'].to_ruby
  end

  def get_legacy_namespace_value(plist)
    result = plist['AD Advanced Options']['AD Use Domain in Username'].to_ruby
    result ? "forest" : "domain"
  end
    
  # This is not authoritative!
  # I wish we could check against computer account authentication, but we do not have SASL support
  # and I don't want to persistently query LDAP with a cleartext password.
  def already_bound?
    # Check dsconfigad for evidence of a bind
    domain        = @options['Active Directory Domain'].eql?(resource[:domain])
    computerid    = @options['Computer Account'].eql?(resource[:computerid])  
    return false unless domain and computerid
    max_tries = 3
    count = 0
    while count < max_tries
      # Perform a a lookup on our host
      notice("Querying DS...")
      if @kernel_version_major < 11
        system("dscl /Search -read /Computers/#{resource[:computerid]} &> /dev/null")
        return true if $?.success?
      else
        system("dscl /Search -read /Computers/#{resource[:computerid]}$ &> /dev/null")
        return true if $?.success?
      end
      restart_directoryservices(10)
      count += 1
    end
    false
  end
  
  # Does both Contacts and Search node config files
  def check_legacy_nodeconfig(config)
    if config.include?('Search Node Custom Path Array')
      return false unless config['Search Node Custom Path Array'].include?(@@legacy_node_name)
    end
    return config['Search Policy'] == 3
  end
  
  def set_legacy_nodeconfig(file)
    file.gsub!(/\.plist$/, "")
    system("defaults write #{file} 'Search Node Custom Path Array' -array-add \'#{@@legacy_node_name}\'")
    return unless $?.success?
    system("defaults write #{file} 'Search Policy' -int 3")
    return $?.success?
  end
  
  def set_legacy_search_and_contacts_path
    if @kernel_version_major < 11
      @@legacy_node_configs.each do |file|
        config = load_legacy_config_file(file)
        return false if config.nil?
        unless check_legacy_nodeconfig(config)
          return unless set_legacy_nodeconfig(file)
        end
      end
      restart_directoryservices(5)
    end
    true
  end
  
  # Not implemented
  # def remove_legacy_search_and_contacts_path
  #   
  # end
  
  def restart_directoryservices(wait)
    if @kernel_version_major < 11
      system('/usr/bin/killall DirectoryService')
    else
      system('/usr/bin/killall opendirectoryd')
    end
    sleep wait
  end
  
  def options_to_args(options_type)
    map = {}
    @resource.parameters.keys.sort.each do |p|
      map[p] = @resource.parameters[p].value.to_s
    end
    args = options_type.collect do |option|
      if option.eql?(:username)
        "-u \'#{map[option]}\'"
      elsif option.eql?(:password)
        "-p \'#{map[option]}\'"
      elsif option.eql?(:computerid)
        "-a \'#{map[option]}\'"      
      elsif map[option] =~ /-no#{option}/
        "#{map[option]}"
      elsif map[option] =~ /^\d+$/
        "-#{option.to_s} #{Integer(map[option])}"
      else
        "-#{option.to_s} \'#{map[option]}\'"
      end
    end
    args
  end
  
  def configure
    return true if @needs_repair.empty? # FIX THIS??? Probably move this to the create method
    notice("Configuring plugin options...")
    `dsconfigad -show &> /dev/null`
    args = options_to_args(@@adv_options)
    system("dsconfigad #{args.join(" ")}")
    return $?.success?
  end
  
  def bind
    notice("Binding to domain...")
    if @kernel_version_major < 11
      system('defaults write /Library/Preferences/DirectoryService/DirectoryService "Active Directory" "Active"')
      return unless $?.success?
      restart_directoryservices(10)
    end
    `dsconfigad -show &> /dev/null`
    @@basic_options.delete(:ou) if @resource.parameters[:ou].value.to_s.empty?
    args = options_to_args(@@basic_options)
    system("dsconfigad -f #{args.join(" ")}")
    return unless $?.success?
    return set_legacy_search_and_contacts_path
  end
  
  def remove
    `dsconfigad -show &> /dev/null`
    system("dsconfigad -f -r \'#{resource[:computerid]}\' -u \'#{resource[:username]}\' -p \'#{resource[:password]}\'")
    return unless $?.success?
    system("/usr/bin/dscacheutil -flushcache")
    return$?.success?
    # return set_legacy_search_and_contacts_path
  end

  
  def wait_for_network(seconds)
    time = 0
    @ldap_servers = ldap_servers
    while time < seconds
      return true if domain_available? and ldap_available?
      time += seconds/3
      sleep seconds/3
    end
    false
  end
  
  # Returns an array of LDAP server names according to the SRV records for the provided domain
  def ldap_servers
    lookup = "_ldap._tcp.#{resource[:domain]}"
    resolver = Resolv::DNS.new
    resolver.getresources(lookup, Resolv::DNS::Resource::IN::ANY).collect { |resource| resource.target }
  end

  def domain_available?
    if @ldap_servers.empty? or @ldap_servers.nil?
      notice("No LDAP SRV records for domain: [#{resource[:domain]}]")
      return false
    end
    true
  end
  
  def ldap_available?
    @ldap_servers.each do |server|
      return true if host_reachable?("#{server}", 10, 389)
    end
    false
  end
  
  # Performs a TCP ping against the specified target
  # Returns Boolean
  def host_reachable?(target='www.google.com', timeout=10, service=80)
    Ping.pingecho(target, timeout, service)
  end
  
end


