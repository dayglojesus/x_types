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
  
  def master
    remaster = render_template(resource[:master])
    realign(remaster)
  end
  
  def master_enabled?
    return false if @master_preferences[@master_label].nil?
    return @master_preferences[@master_label].to_ruby.eql?(@master_path)
  end
  
  def load_master
    @master_preferences[@master_label] = @master_path
    @master_preferences
  end

  def unload_master
    @master_preferences.delete(@master_label)
    @master_preferences
  end
  
  def hook_path
    return resource[:name] if resource[:name] =~ /^\//
    "#{@hooks_dir}/#{resource[:name]}"
  end
  
  # This will need to be expanded so that it handles resource[:file]
  def hook
    hook = realign(resource[:content]) || read_content_from_disk(@hook_path)
    unless resource[:ensure].to_s.eql?('absent')
      fail("Executable content not specified and #{@hook_path} does not exist.") if hook.empty?
    end
    hook
  end
    
  def load_plist(file)
    NSMutableDictionary.dictionaryWithContentsOfFile(file)
  end
  
  def hook_loaded?
    return false if @hooks_array.empty?
    return @hooks_array.include?(@hook_record)
  end
  
  def load_hook
    @hooks_array << @hook_record
    @preferences[resource[:type].to_s + 'hooks'] = @hooks_array
  end
  
  def unload_hook
    @hooks_array.delete(@hook_record)
    @preferences[resource[:type].to_s + 'hooks'] = @hooks_array
  end
  
  def write_preferences(dict, path)
    dict.writeToFile_atomically(path, true)
  end
  
  def content_matches_file?(content, path)
    file = read_content_from_disk(path)
    content.eql?(file)
  end
  
  def create_hooks_dir(hooks_dir)
    begin
      FileUtils.mkdir_p(hooks_dir)
      FileUtils.chown_R('root', 'admin', hooks_dir)
      FileUtils.chmod_R(0750, hooks_dir)
    rescue => error
      raise("Could not create dir #{hooks_dir}: #{error.message}")
    end
  end
  
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
  
  def write_content_to_disk(source, path)
    begin
      File.open(path, 'w') { |f| f.write(source)}
      FileUtils.chmod(0700, path)
    rescue => error
      raise("Could not write file to disk: #{error.message}")
    end
  end
  
  def render_template(template)
    doc = ERB.new(template, 0, "%<>")
    # doc.run(self.send(:binding))
    doc.result(self.send(:binding))
  end
  
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
