# Type: x_computergroup
# Created: Mon Nov 28 09:52:24 PST 2011

Puppet::Type.newtype(:x_computergroup) do
  @doc = "Manage Mac OS X ComputerGroup objects
    x_computergroup { 'mynewgroup':
      dslocal_node  => 'MyNode'
      computers     =>['foo','bar','baz'],
      gid           => '5000',
      ensure        => present
    }"

  ensurable

  newparam(:name) do
    desc "The name of the group to manage."
    isnamevar
  end

  newparam(:dslocal_node) do
    desc "The name of the node to manage."
  end

  newparam(:computers) do
    desc "An array containing a list of computers to add to the designated group."
  end

  # Not implemented
  # newparam(:computergroups) do
  #   desc "An array containing a list of computergroups to nest in the designated group."
  # end

  newparam(:gid) do
    desc "Numeric group identifier assigned to the computer group."
  end

  newparam(:autocratic) do
    desc "Setting this to true will explicitly define which computers are members of the target computer group. This
          means that any record not defined in the :computers array will be removed if present.
          NOTE: Nested computer groups, if they exist are outside the scope of management. These records, if defined,
          will remain untouched."
    newvalues(true, false, :enable, :enabled, :disable, :disabled)
    defaultto false
  end
  
end
