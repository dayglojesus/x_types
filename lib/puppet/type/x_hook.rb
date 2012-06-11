# Type: x_hook
# Created: Thu May  3 09:23:19 PDT 2012

Puppet::Type.newtype(:x_hook) do
  @doc = "Manages Mac OS X login/logout hooks"
  
  ensurable
  
  newparam(:name) do
    desc "The name of the script to to enable. If the path is specified without a qualifying
    path, the provider will search for it in /private/etc/x_types/x_hooks. If the script is
    non-existent and no :content is specified, the provider will raise an error."
    isnamevar
  end

  newparam(:content) do
    desc "Executable content embedded in the resource definition. You can use this
    in place of an actual local file, and the provider will create the file for you."
  end

  newparam(:type) do
    desc "When to enable the script, at login or logout."
    newvalues(:login, :logout)
    defaultto :login
  end

    
  newparam(:priority) do
    desc "The priority execution of the hook represented as an integer. Zero is the highest 
    priority."
  end
    
  newparam(:master) do
    desc "Embedded executable content for the master hooks. You may edit this content to suit
    your specific needs, but use caution.
    
    All master hooks, as well as any hooks without specific paths will be written into the
    /private/etc/x_types/x_hooks directory.
    "
    
    master_hook_template = %q{
      #!/usr/bin/ruby

      require 'osx/cocoa'    
      require 'syslog'
      require 'fileutils'
      require 'etc'

      include OSX

      @type         = '<%= resource[:type] %>'
      @label        = @type + 'hooks'
      @log          = Syslog.open('x_hook')
      @username     = ARGV.join(' ')
      @user_info    = Etc.getpwnam(@username)
      @preferences  = '/Library/Preferences/com.puppetlabs.x_types.plist'

      def load_plist(file)
        NSMutableDictionary.dictionaryWithContentsOfFile(file)
      end

      # Sort by value (int), then by key (alpha)
      # http://stackoverflow.com/questions/4790796/sorting-a-hash-in-ruby-by-its-value-first-then-its-key
      def prioritize_hooks(array_of_dicts)
        compiled = Hash.new
        array_of_dicts.each { |e| compiled.merge!(e) } 
        ordered = compiled.sort_by { |x, y| [ -Integer(y), x ] }
        ordered.collect! { |array| array[0] }
      end

      @log.notice("#{@type.capitalize}: #{@username}, uid=#{@user_info.uid}, gid=#{@user_info.gid}")

      @hooks = prioritize_hooks(load_plist(@preferences)[@label].to_ruby)

      @hooks.each_with_index do |hook, priority|
        if File.executable?(hook)
          @log.notice("=> Exec: #{hook} #{@username}, [Priority: #{priority}]")
          system(hook, "#{@username}", "#{@user_info.uid}", "#{@user_info.gid}")
        else
          @log.notice("=> Error: #{hook} is not a valid executable.")
        end
      end

      @log.notice("#{@type.capitalize}: #{@username}, complete.")
      # @log.notice("Complete")

      Syslog.close

      exit 0
    }
    
    defaultto { master_hook_template }
    
  end
    
end
