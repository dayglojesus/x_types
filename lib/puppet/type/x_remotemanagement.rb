# Type: remotedesktop
# Created: Fri Feb  3 11:22:04 PST 2012, bcw@sfu.ca

Puppet::Type.newtype(:x_remotemanagement) do
  @doc = "Manage Mac OS X Apple Remote Desktop client settings.
    remotemanagement { 'setup_ard':
      vnc         => 'enable',
      vncpass     => 'foobar',
      menuextra   => 'disabled',
      dirlogins   => 'enabled',
      users       => {'fred' => -1073741569, 'daphne' => -2147483646, 'velma' => -1073741822 },
      ensure      => 'running',
    }
    
    === EXAMPLE USER PRIVILEDGE SETTINGS ===
    Bit map for naprivs
    -------------------
    64 Bit Hex Int Bit Decimal Checkbox Item
    ================================================================
    FFFFFFFFC0000000 0 -1073741824 enabled but nothing set
    FFFFFFFFC0000001 1 -1073741823 send text msgs
    FFFFFFFFC0000002 2 -1073741822 control and observe, show when observing
    FFFFFFFFC0000004 3 -1073741820 copy items
    FFFFFFFFC0000008 4 -1073741816 delete and replace items
    FFFFFFFFC0000010 5 -1073741808 generate reports 
    FFFFFFFFC0000020 6 -1073741792 open and quit apps
    FFFFFFFFC0000040 7 -1073741760 change settings
    FFFFFFFFC0000080 8 -1073741696 restart and shutdown
    
    FFFFFFFF80000002 -2147483646 control and observe don't show when observing
    FFFFFFFFC00000FF -1073741569 all enabled
    "

  # Handle whether the service should actually be running right now.
  newproperty(:ensure) do
    desc "Whether a service should be running."

    newvalue(:stopped, :event => :service_stopped) do
      provider.stop
    end

    newvalue(:running, :event => :service_started) do
      provider.start
    end

    aliasvalue(:false, :stopped)
    aliasvalue(:true, :running)

    def retrieve
      provider.running?
    end

    def sync
      event = super()
      if property = @resource.property(:enable)
        val = property.retrieve
        property.sync unless property.safe_insync?(val)
      end
      event
    end
  end
      
  newparam(:name) do
    desc "Name of the setup."
    isnamevar
  end

  newparam(:menuextra) do
    desc "Enable or disable the ARD menu extra in the user's task bar."
    newvalues(true, false, :enable, :enabled, :disable, :disabled)
    defaultto true
  end

  newparam(:dirlogins) do
    desc "Allow the special directory groups to be used."
    newvalues(true, false, :enable, :enabled, :disable, :disabled)
    defaultto false
  end
  
  newparam(:dirgroups) do
    desc "A hash sepcifying which directory groups are allowed."
    defaultto ""
  end  
  
  newparam(:vnc) do
    desc "Enable or disable legacy VNC support."
    newvalues(true, false, :enable, :enabled, :disable, :disabled)
    defaultto false
  end

  newparam(:vncpass) do
    desc "The password use for VNC, stored as plain text! Thinking this is not a good idea? Yeah, me too. Don't use it."
    defaultto ""
  end

  newparam(:vncreqperm) do
    desc "Allow VNC guests to request permission?"
    newvalues(true, false, :enable, :enabled, :disable, :disabled)
    defaultto false
  end
  
  newparam(:webem) do
    desc "Allow incoming WBEM requests over IP?"
    newvalues(true, false, :enable, :enabled, :disable, :disabled)
    defaultto false
  end
  
  newparam(:users) do
    desc "A hash containing a username to privilege mapping."
    defaultto { return { 'all' => '0' } }
  end
  
  # Maybe rename this to :mode and specify 3 modes: autocratic, shared, once
  newparam(:autocratic) do
    desc "Setting this to true will explicitly define which users are permitted RemoteManagement privs. This
          means that any account not defined in the :users hash will have their privs revoked if present."
    newvalues(true, false, :enable, :enabled, :disable, :disabled)
    defaultto false
  end
    
end
