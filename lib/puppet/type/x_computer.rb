# Type: x_computer
# Created: Mon Dec  5 12:19:52 PST 2011
Puppet::Type.newtype(:x_computer) do
  @doc = "Manage Mac OS X Computer records in arbitrary local nodes
    x_computer { 'my_computer':
      dslocal_node  => 'MyNode',
      en_address    => 'ff:ff:ff:ff:ff:ff',
      hardware_uuid => \"$::sp_platform_uuid\",
      ensure        => 'present'
    }"

  ensurable

  newparam(:name) do
    desc 'The name of the computer record to manage.'
    isnamevar
  end

  newparam(:dslocal_node) do
    desc 'The name of the node to manage. Default is "Default".'
    defaultto 'Default'
  end

  newparam(:en_address) do
    desc 'The MAC address of the machine.'
  end

  newparam(:hardware_uuid) do
    desc 'The machine specific hardware UUID.'
  end
  
end