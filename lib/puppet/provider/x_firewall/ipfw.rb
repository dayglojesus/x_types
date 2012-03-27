# Provider: ipfw
# Created: Mon Nov 21 15:08:36 PST 2011

# TODO
# - optimize so that configs are re-applied atomically, not wholesale
# - implement rules read from "rules" array
# - allow merge of rules from file and array

Puppet::Type.type(:x_firewall).provide(:ipfw) do
  desc "Provides ipfw support for the firewall type."

  commands :ipfwcmd   => "/sbin/ipfw"
  commands :sysctlcmd => "/usr/sbin/sysctl"

  def start
    info("Enabling firewall... [ipfw]")
    sysctlcmd "-w", "net.inet.ip.fw.enable=1"
    sysctlcmd "-w", "net.inet.ip.fw.verbose=#{resource[:verbosity].to_i}"
    add_rules(@rules_from_file)
  end

  def stop
    info("Disabling firewall... [ipfw]")
    ipfwcmd "-f flush"
    sysctlcmd "-w", "net.inet.ip.fw.verbose=0"
    sysctlcmd "-w", "net.inet.ip.fw.enable=0"
  end

  def running?
    info("Inspecting firewall... [ipfw]")
    @rules_from_file = get_rules_from_file
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
    if @current_rules.eql?(@rules_from_file)
      notice('Firewall OK')
      return :running
    else
      notice('Firewall rules do not match policy...')
      return :stopped
    end
  end
  
  def get_rules_from_file
    File.open(resource[:file]).readlines.collect(&:chomp)
  end
  
  def add_rules(rules)
    ipfwcmd "-f flush"
    rules.each { |rule| ipfwcmd "add #{rule}" }
  end
  
end
