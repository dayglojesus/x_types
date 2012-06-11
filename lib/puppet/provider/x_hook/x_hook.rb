# Provider: x_hook
# Created: Thu May  3 09:23:19 PDT 2012

begin
  require 'osx/cocoa'
  require 'fileutils'
  require 'erb'
  require 'pp'
  include OSX
rescue
  puts "Are you still there?"
end

Puppet::Type.type(:x_hook).provide(:x_hook) do

  desc "Configure Mac OS X login and logout hooks."

  commands    :dscl => "/usr/bin/dscl"
  confine     :operatingsystem => :darwin
  defaultfor  :operatingsystem => :darwin
  
  @@loginwindow_prefs = '/private/var/root/Library/Preferences/com.apple.loginwindow.plist'
  @@x_types_prefs     = '/Library/Preferences/com.puppetlabs.x_types.plist'
  
  def create
    notice("Creating resource...")
    create_hooks_dir(@hooks_dir)
    load_hook unless hook_loaded?
    write_content_to_disk(@hook, @hook_path)
    write_preferences(@preferences, @@x_types_prefs)
    load_master unless master_enabled?
    write_content_to_disk(@master, @master_path)
    write_preferences(@master_preferences, @@loginwindow_prefs)
    true
  end
  
  def destroy
    notice("Destroying resource...")
    unload_hook
    FileUtils.rm(@hook_path)
    write_preferences(@preferences, @@x_types_prefs)
    if @hooks_array.empty?
      unload_master
      FileUtils.rm(@master_path)
      write_preferences(@master_preferences, @@loginwindow_prefs)
    else
      info("Cannot unload master hook while other hooks remain defined.")
    end
    true
  end

  def exists?
    notice("Checking resource...")
    # Hook
    @preferences = load_plist(@@x_types_prefs) || NSMutableDictionary.new
    @hooks_dir = '/private/etc/x_types/x_hooks'
    @hooks_array = @preferences[resource[:type].to_s + 'hooks'] || NSMutableArray.new
    @hook_path = hook_path
    @hook_record = { @hook_path => resource[:priority].to_i }.to_ns
    @hook = hook
    # Master
    @master_preferences = load_plist(@@loginwindow_prefs) || NSMutableDictionary.new
    @master_path = "#{@hooks_dir}/_#{resource[:type]}hook.master"
    @master_label = resource[:type].to_s.capitalize + 'Hook'
    @master = master
    # Checks
    return unless File.exists?(@hooks_dir)
    return unless hook_loaded?
    return unless content_matches_file?(@hook, @hook_path)
    return unless content_matches_file?(@master, @master_path)
    return unless master_enabled?
    true
  end
  
  # The master hoook is an ERB template; render it
  def master
    remaster = render_template(resource[:master])
    realign(remaster)
  end
  
  # Master hook already defined in the root loginwindow prefs?
  def master_enabled?
    return false if @master_preferences[@master_label].nil?
    return @master_preferences[@master_label].to_ruby.eql?(@master_path)
  end
  
  # Enable the master hook by adding the defined key to the root loginwindow prefs
  def load_master
    @master_preferences[@master_label] = @master_path
    @master_preferences
  end

  # Remove the appropriate key from the root loginwindow prefs
  def unload_master
    @master_preferences.delete(@master_label)
    @master_preferences
  end
  
  # Decide which path to use, an absolute path OR a path relative to our @hooks_dir
  def hook_path
    return resource[:name] if resource[:name] =~ /^\//
    "#{@hooks_dir}/#{resource[:name]}"
  end
  
  # Load the :content as hook OR read content from @hook_path
  def hook
    hook = realign(resource[:content]) || read_content_from_disk(@hook_path)
    unless resource[:ensure].to_s.eql?('absent')
      fail("Executable content not specified and #{@hook_path} does not exist.") if hook.empty?
    end
    hook
  end
  
  # Load a Property List
  def load_plist(file)
    NSMutableDictionary.dictionaryWithContentsOfFile(file)
  end
  
  # Is the hook defined in the appropriate @hooks_array in our x_type prefs?
  def hook_loaded?
    return false if @hooks_array.empty?
    return @hooks_array.include?(@hook_record)
  end
  
  # Define the hook in the appropriate @hooks_array in our x_type prefs
  def load_hook
    @hooks_array << @hook_record
    @preferences[resource[:type].to_s + 'hooks'] = @hooks_array
  end
  
  # Remove the hook from the appropriate @hooks_array in our x_type prefs
  def unload_hook
    @hooks_array.delete(@hook_record)
    @preferences[resource[:type].to_s + 'hooks'] = @hooks_array
  end
  
  # Write an NSDictionary to disk to store our preferences
  def write_preferences(dict, path)
    dict.writeToFile_atomically(path, true)
  end
  
  # Compare the contents of a variable with that of a file on disk
  def content_matches_file?(content, path)
    file = read_content_from_disk(path)
    content.eql?(file)
  end
  
  # Create the basic dir structure for storing hooks
  def create_hooks_dir(hooks_dir)
    begin
      FileUtils.mkdir_p(hooks_dir)
      FileUtils.chown_R('root', 'admin', hooks_dir)
      FileUtils.chmod_R(0750, hooks_dir)
    rescue => error
      raise("Could not create dir #{hooks_dir}: #{error.message}")
    end
  end
  
  # Read in a file
  def read_content_from_disk(path)
    content = String.new
    begin
      return content unless File.executable?(path)
      f = File.new(path)
      content = f.read
      f.close
    rescue
      String.new
    end
    content
  end
  
  # Write out a file
  def write_content_to_disk(source, path)
    begin
      File.open(path, 'w') { |f| f.write(source)}
      FileUtils.chmod(0700, path)
    rescue => error
      raise("Could not write file to disk: #{error.message}")
    end
  end
  
  # Render an EB template
  def render_template(template)
    doc = ERB.new(template, 0, "%<>")
    # doc.run(self.send(:binding))
    doc.result(self.send(:binding))
  end
  
  # Realigns multiline content to margin; very primative
  # Strips blank lines -- not so great
  def realign(content)
    return nil unless content
    content = content.split("\n")
    content.delete_if { |e| e.empty? }
    content.first =~ /^[\s|\t]+/
    indent = $~
    content.collect! do |line|
      line.sub!(/#{indent}/, '')
      line.rstrip!
      line
    end
    content.join("\n")
  end
    
end
