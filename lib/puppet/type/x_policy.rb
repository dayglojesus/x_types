# Type: x_mcx
# Created: Wed Feb 15 07:49:15 PST 2012

Puppet::Type.newtype(:x_policy) do
  @doc = "Manage Mac OS X MCX Policy on DirectoryService entities in targeted nodes
    x_policy { 'SoftwareUpdate':
      provider      => 'x_mcx',
      dslocal_node  => 'MCX',
      type          => 'computergroup',
      plist         => '/private/etc/policy/mcx/policy.plist',
      ensure        => 'present'
    }

    The default provider of this type merely manages the XML plist as
    reported by the dscl -mcxexport command.  This is similar to the
    content property of the file type in Puppet.
  "
  ensurable
  
  newparam(:name) do
    isnamevar
  end

  newparam(:type) do
    desc "The DirectoryService type this MCX setting attaches to. This value is explicitly required."
    newvalues(:user, :group, :computer, :computergroup)
  end

  newparam(:dslocal_node) do
    desc 'The name of the node to manage. Default is "Default".'
    defaultto 'Default'
  end

  newparam(:plist) do
    desc "An XML Property List containing the policy to be applied to the target entity."
    validate do |value|
      unless value =~ /^\/[a-z0-9]+/
        raise ArgumentError, "%s is not a valid file path" % value
      end
    end
  end

  newproperty(:content) do
    desc "An XML string representation (inc'l newlines) of the MCX Property List"
  end
  
  newparam(:autocratic) do
    desc "Setting this to true will explicitly define policy on the target record. This
          means that any policy not defined in the :content or :plist attributes will be 
          removed prior to application of defined policy. This essentially controls how 
          policy is masked.
          
          Policy defined in the Puppet resource ALWAYS takes precedence over any previously
          defined policy.
          
          EXAMPLE:
          Your :plist sets policy A, but some local administrator has also manually set 
          policy B on the same target record. 
          
          Provided the two policies do not collide, when Puppet is run, only the policy 
          in the :plist (policy A) will be applied, leaving policy B intact. 
          
          However, if :autocratic is 'true', all policy in the record will be expunged 
          prior to application, thereby removing policy B and making the policy in :plist 
          (policy A) explicit.
          "
    newvalues(true, false, :enable, :enabled, :disable, :disabled)
    defaultto false
  end
  
end
