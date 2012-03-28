# Provider: ipfw
# Created: Mon Nov 21 15:08:36 PST 2011

Puppet::Type.type(:x_firewall).provide(:ipfw) do
  desc "Provides ipfw support for the firewall type."

  commands :ipfwcmd   => "/sbin/ipfw"
  commands :sysctlcmd => "/usr/sbin/sysctl"

  def start
    info("Enabling firewall... [ipfw]")
    sysctlcmd "-w", "net.inet.ip.fw.enable=1"
    sysctlcmd "-w", "net.inet.ip.fw.verbose=#{resource[:verbosity].to_i}"
    add_rules(@specified_rules)
  end

  def stop
    info("Disabling firewall... [ipfw]")
    ipfwcmd "-f flush"
    sysctlcmd "-w", "net.inet.ip.fw.verbose=0"
    sysctlcmd "-w", "net.inet.ip.fw.enable=0"
  end

  def running?
    info("Inspecting firewall... [ipfw]")
    @specified_rules = get_rules
    ipfw_enable   = `/usr/sbin/sysctl -n net.inet.ip.fw.enable`.chomp.to_i.eql?(1)
    ipfw_verbose  = `/usr/sbin/sysctl -n net.inet.ip.fw.verbose`.chomp.to_i.eql?(resource[:verbosity].to_i)
    unless ipfw_enable
      notice("Firewall disabled!") unless resource[:ensure].eql?(:stopped)
      @state = :stopped
    end
    unless ipfw_verbose
      notice("Firewall logging disabled!") unless resource[:ensure].eql?(:stopped)
      @state = :stopped
    end
    return @state if @state.eql?(:stopped)
    @current_rules = `/sbin/ipfw list`.split("\n")
    default_rule = @current_rules.pop
    if @current_rules.eql?(@specified_rules)
      notice('Firewall OK')
      return :running
    else
      notice('Firewall rules do not match policy...')
      return :stopped
    end
  end
  
  # Rules specified in the :rules attribute take precedence over
  # those specified in :file
  def get_rules
    internal, external = [], []
    if resource[:rules]
      internal = resource[:rules].sort
    end
    if resource[:file]
      external = get_rules_from_file(resource[:file]).sort 
    end
    compose(internal, external)
  end
  
  def compose(set_a, set_b)
    rules = set_a | set_b
    rules.sort
  end
  
  # Reads in rules from the specified file
  # Returns an array or rules
  def get_rules_from_file(file)
    file = resource[:file]
    if File.exists?(file)
      return File.open(file).readlines.collect(&:chomp)
    else
      fail("The rule set specifed does not exist: #{file}")
    end
  end
  
  def add_rules(rules)
    ipfwcmd "-f flush"
    rules.each { |rule| ipfwcmd "add #{rule}" }
  end
  
end
