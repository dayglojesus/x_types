# Provider: ipfw
# Created: Mon Nov 21 15:08:36 PST 2011, bcw@sfu.ca

# TODO
# - optimize so that configs are not re-applied atomically, not wholesale
# - implement rules read from "rules" array
# - allow merge of rules from file and array

Puppet::Type.type(:x_firewall).provide(:ipfw) do
  desc "Provides ipfw support for the firewall type."

  commands :ipfwcmd   => "/sbin/ipfw"
  commands :sysctlcmd => "/usr/sbin/sysctl"

  def create
    sysctlcmd "-w", "net.inet.ip.fw.enable=1"
    sysctlcmd "-w", "net.inet.ip.fw.verbose=#{resource[:verbosity].to_i}"
    add_rules
  end

  def destroy
    sysctlcmd "-w", "net.inet.ip.fw.enable=0"
  end

  def exists?
    @rules_from_file = get_rules_from_file
    @rules = @rules_from_file
    return unless (sysctlcmd "-n", "net.inet.ip.fw.enable").chomp.to_i.eql?(1)
    return unless (sysctlcmd "-n", "net.inet.ip.fw.verbose").chomp.to_i.eql?(resource[:verbosity].to_i)
    current_rules = `ipfw list`.split("\n")
    default_rule = current_rules.pop
    current_rules.eql?(@rules)
  end
  
  def get_rules_from_file
    File.open(resource[:file]).readlines.collect(&:chomp)
  end
  
  def add_rules
    ipfwcmd "-f flush"
    @rules.each { |rule| ipfwcmd "add #{rule}" }
  end
  
end