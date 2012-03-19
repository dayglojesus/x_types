# Type: x_node
# Created: Sat Mar  3 12:26:01 PST 2012, bcw@sfu.ca

Puppet::Type.newtype(:x_node) do
  @doc = "Manage Mac OS X Directory Service nodes
  
  1. Using the 'dslocal' Provider:
    x_node { 'newnode':
      active  => 'true',
      ensure  => 'present'
    }
  
  2. Using the 'activedirectory' Provider:
    x_node { 'some.domain':
      active        => 'true',
      ensure        => 'present'
      provider      => 'activedirectory',
      active        => 'true',
      computerid    => 'some_machine',
      username      => 'some_user',
      password      => 'a_password',
      ou            => 'CN=Computers',
      domain        => 'some.domain',
      mobile        => 'disable',
      mobileconfirm => 'disable',
      localhome     => 'disable',
      useuncpath    => 'enable',
      protocol      => 'afp',
      shell         => '/bin/false',
      groups        => 'SOME_DOMAIN\some_group,SOME_DOMAIN\another_group',
      passinterval  => '0',     
    }"

  ensurable
      
  newparam(:active) do
    desc "Add/Remove node from the search path: true or false."
    newvalues(:true, :false)
    defaultto :true
  end
  
  newparam(:computerid) do
    desc "name of computer to add to domain"
    defaultto Facter.hostname
  end
  
  # Not implemented
  # * I can't implement this until we use SASL binding. Perhaps after dropping support for 10.5.8?
  # * We need Ruby 1.8.7 and a working gems installation.
  # newparam(:force) do 
  #   desc "This behaves in the OPPOSITE manner as the dsconfigad util. 
  #   This provider will not bind unless there is an existing computer 
  #   account for the designated host.
  #   Thus, enabling this parameter forces binding regardless of whether 
  #   or not there is an existing computer account.
  #   
  #   If you have not pre-created a computer account for the designated 
  #   host, YOU MUST enable this parameter.
  #   "
  #   newvalues(:true, :false, :enable, :disable)
  #   defaultto :false
  # end

  newparam(:username) do 
    desc "username of a privileged network user"
    validate do |value|
      if value.eql?("") or value.nil?
        raise ArgumentError, "This parameter is required. \'%s, [%s]\' is not a valid paramter." % value, value.class
      end
    end
  end

  newparam(:password) do 
    desc "password of a privileged network user"
    validate do |value|
      if value.eql?("") or value.nil?
        raise ArgumentError, "This parameter is required. \'%s, [%s]\' is not a valid paramter." % value, value.class
      end
    end
  end

  newparam(:ou) do 
    desc "fully qualified LDAP DN of container for the computer
    (defaults to CN=Computers)"
    munge do |value|
      "#{value.to_s}"
    end
    defaultto 'CN=Computers'
  end

  newparam(:domain) do 
    desc "fully qualified DNS name of Active Directory Domain"
    isnamevar
  end

  ######## AD Plugin Options: User Experience ########
  #
  newparam(:mobile) do
    desc "'enable' or 'disable' mobile user accounts for offline use
    aka 'Create mobile account at login"
    newvalues(:enable, :disable)
    defaultto :disable
  end

  newparam(:mobileconfirm) do
    desc "'enable' or 'disable' warning for mobile account creation
    aka 'Require confirmation before creating a mobile account'"
    newvalues(:enable, :disable)
    defaultto :enable
  end

  newparam(:localhome) do
    desc "'enable' or 'disable' force home directory to local drive
    aka 'Force local home directory on startup disk'"
    newvalues(:enable, :disable)
    defaultto :enable
  end

  newparam(:useuncpath) do
    desc "'enable' or 'disable' use Windows UNC for network home
    aka 'Use UNC path from Active Directory to derive network home location'"
    newvalues(:enable, :disable)
    defaultto :enable
  end

  newparam(:protocol) do
    desc "'afp' or 'smb' change protocol used when mounting home
    aka 'Network protocol to be used'"
    newvalues(:smb, :afp)
    defaultto :smb
  end

  newparam(:shell) do
    desc "'none' for no shell or specify a default shell '/bin/bash'
    aka 'Default user shell'"
    defaultto '/bin/bash'
  end

  ########  AD Plugin Options: Mappings ########

  newparam(:uid) do
    desc "name of attribute to be used for UNIX uid field"
    defaultto '-nouid'
  end

  newparam(:gid) do 
    desc "name of attribute to be used for UNIX gid field"
    defaultto '-nogid'
  end
  
  newparam(:ggid) do 
    desc "name of attribute to be used for UNIX group gid field"
    defaultto '-noggid'
  end
  
  # This value is an odd-ball:
  # This value is LION ONLY! and COMMAND LINE ONLY!
  newparam(:authority) do 
    desc "enable or disable generation of Kerberos authority"
    newvalues(:enable, :disable)
    defaultto :enable
  end
  
  ######## AD Plugin Options: Administrative ########

  newparam(:preferred) do 
    desc "fully-qualified domain name of preferred server to query
    aka 'Prefer this domain server'"
    defaultto '-nopreferred'
  end

  newparam(:groups) do 
    desc "list of groups that are granted Admin privileges on local
    aka 'Allow administration by'"
    munge do |value|
      case value
      when Array
        "#{value.join(",")}"
      else
        "#{value.to_s}"
      end
    end
    defaultto '-nogroups'
  end

  newparam(:alldomains) do 
    desc "'enable' or 'disable' allow authentication from any domain
    aka 'Allow administratoin form any domain in the forest'"
    newvalues(:enable, :disable)
    defaultto :enable
  end

  newparam(:packetsign) do 
    desc "'disable', 'allow', or 'require' packet signing"
    newvalues(:disable, :allow, :require)
    defaultto :allow
  end

  newparam(:packetencrypt) do 
    desc "'disable', 'allow', 'require' or 'ssl' packet encryption"
    newvalues(:disable, :allow, :require)
    defaultto :allow
  end

  newparam(:namespace) do 
    desc "'forest' or 'domain', where forest qualifies all usernames"
    newvalues(:forest, :domain)
    defaultto :domain
  end

  newparam(:passinterval) do 
    desc "how often to change computer trust account password in days"
    munge do |value|
      case value
      when String
        Integer(value)
      else
        value
      end
    end
    validate do |value|
      if value.to_s !~ /^\d+$/
        raise ArgumentError, "Password minimum age must be provided as a number."
      end
    end
    defaultto 14
  end
  
  # This value is LION ONLY! and COMMAND LINE ONLY!
  newparam(:restrictddns) do 
    desc "list of interfaces to restrict DDNS to (en0, en1, etc.)"
    defaultto do
      nil
    end
  end
  
end
