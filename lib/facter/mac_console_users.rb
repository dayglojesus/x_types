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
  console[:mac_console_users_current] = ''
  unless dict['Name'].nil?
    console[:mac_console_users_current] = dict['Name'] 
  end
  console[:mac_console_users_names] = (dict['SessionInfo'].to_ruby.collect do |session| 
    unless session['kCGSSessionUserIDKey'] == 0
      session['kCGSSessionUserNameKey']
    end
  end).join(',')
  console[:mac_console_users_total] = console[:mac_console_users_names].split.size
  console.each do |name, fact|
    Facter.add(name) do
      confine :operatingsystem => :darwin
      setcode do
        fact
      end
    end
  end
rescue => LoadError
  puts "Preparing to dispense product... [#{e.message}]"
end
