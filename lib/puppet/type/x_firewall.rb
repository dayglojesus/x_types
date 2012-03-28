# Type: x_firewall
# Created: Mon Nov 21 15:21:30 PST 2011

Puppet::Type.newtype(:x_firewall) do
  @doc = "Manage Mac OS X firewall.
    x_firewall { 'ipfw_setup':
      rules => ['12300 allow tcp from any to any established'],
      file => '/private/etc/ipfw/ipfw.rules',
      verbosity => '2',
      ensure => present
    }"

  # Handle whether the service should actually be running right now.
  newproperty(:ensure) do
    desc "Whether the service should be running."

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
    
    defaultto :running
    
  end

  newparam(:type) do
    desc "The type of firewall to enable."
    validate do |value|
      if value =~ /ipfw/
        resource[:provider] = :ipfw
      else
        resource[:provider] = :alf
      end
    end
    isnamevar
  end

  newparam(:rules) do
    desc "An array containing a list of firewall rules to be enabled.
          When the provider encounters two rulesets, it merges them. Duplicate rules
          are discarded, and the rules specified in the :rules attribute are given
          precedence.
          "
  end

  newparam(:file) do
    desc "A file containing a list of firewall rules to be enabled.
          When the provider encounters two rulesets, it merges them. Duplicate rules
          are discarded, and the rules specified in the :rules attribute are given
          precedence.
          "
    validate do |value|
        unless value =~ /^\/[a-z0-9]+/
            raise ArgumentError, "%s is not a valid file path" % value
        end
    end
  end

  newparam(:verbosity) do
    desc "Configures logging verbosity."
  end

  # Not implemented
  # This idea is silly. Need to be able to combine rules sensibly. Until, have the
  # the provider do simple a merge.
  # newparam(:autocratic) do
  #   desc "By default, you can define two sets of rules: one directly in the resource
  #         using the :rules attribute, and one in an external location using :file.
  #         
  #         When the provider encounters two rulesets, it merges them. Duplicate rules
  #         are discarded, and the rules specified in the :rules attribute are given
  #         precedence.
  #         
  #         Enabling this attribute effectively tells the provider to use the first set 
  #         of rules it finds and ignore any other rulesets.
  #         "
  #   newvalues(true, false, :enable, :enabled, :disable, :disabled)
  #   defaultto false
  # end
  
  # Ensure we always have rules
  # validate do
  #   unless @parameters.include?(:file) or @parameters.include?(:rules)
  #     raise Puppet::Error, "You must specify at least one set of rules." 
  #   end
  # end
  
end
