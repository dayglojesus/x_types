require 'puppet'

begin
  require 'osx/cocoa'
  include OSX
  OSX.require_framework('SystemConfiguration')
  console = {}
  sc_dynstore_session_name  = Proc.new { 'Facter_mac_console_users' }
  sc_dynstore_session       = SCDynamicStoreCreate(nil, sc_dynstore_session_name.call, nil, nil)
  key   = SCDynamicStoreKeyCreateConsoleUser(nil)
  dict  = SCDynamicStoreCopyValue(sc_dynstore_session, key)
  console[:mac_console_users_names]   = dict['SessionInfo'].to_ruby.collect { |x| x['kCGSSessionUserNameKey'] }.join(',')
  console[:mac_console_users_current] = dict['Name']
  console[:mac_console_users_total]   = dict['SessionInfo'].to_ruby.size
  console.each do |name, fact|
    Facter.add(name) do
      setcode do
        fact
      end
    end
  end
rescue => e
  puts "Preparing to dispense product... [#{e.message}]"
end