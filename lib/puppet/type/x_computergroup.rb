# Type: dslocal_computergroup
# Created: Mon Nov 28 09:52:24 PST 2011, bcw@sfu.ca
Puppet::Type.newtype(:x_computergroup) do
  @doc = "Manage Mac OS X ComputerGroup objects
    dslocal_computergroup { 'mynewgroup':
      dslocal_node  => 'MyNode'
      members       =>['foo','bar','baz'],
      gid           => '5000',
      ensure        => present
    }"

  ensurable do
    newvalue(:present) do
      provider.create
    end
    newvalue(:absent) do
      provider.destroy
    end
    defaultto :present
  end

  newparam(:name) do
    desc "The name of the group to manage."
    isnamevar
  end

  newparam(:dslocal_node) do
    desc "The name of the node to manage."
  end

  newparam(:members) do
    desc "An array containing a list of computers to add to the designated group."
  end

  newparam(:gid) do
    desc "Numeric group identifier assigned to the computer group."
  end
  
end