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

    **Autorequires:** If Puppet is managing the user, group, or computer that these
    MCX settings refer to, the MCX resource will autorequire that user, group, or computer.
  "

  # feature :manages_content, "The provider can manage MCXSettings as a string.", :methods => [:content, :content=]

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

  newproperty(:content, :required_features => :manages_content) do
    desc "An XML string representation (inc'l newlines) of the MCX Property List"
  end

  # JJM Yes, this is not DRY at all.  Because of the code blocks
  # autorequire must be done this way.  I think.
  # def setup_autorequire(type)
  #   # value returns a Symbol
  #   name = value(:name)
  #   ds_type = value(:type)
  #   ds_name = value(:name)
  #   if ds_type == type
  #     rval = [ ds_name.to_s ]
  #   else
  #     rval = [ ]
  #   end
  #   rval
  # end
  
  # I don't think any of this works...
  # Thu Feb 16 11:35:58 PST 2012
  
  # autorequire(:user) do
  #   setup_autorequire(:user)
  # end
  # 
  # autorequire(:group) do
  #   setup_autorequire(:group)
  # end
  # 
  # autorequire(:computer) do
  #   setup_autorequire(:computer)
  # end
  # 
  # autorequire(:computergroup) do
  #   setup_autorequire(:computergroup)
  # end

end
