require 'fileutils'
require 'fog'
require 'slop'

LOG_CONFIG = YAML.load_file('dump_config.yml')

options = Slop.parse do
  banner 'Usage: dump_logs.rb [options]'
  on :access_key=, 'Amazon S3 Access Key'
  on :secret_key=, 'Amazon S3 Secret key'
  on :bucket_name=, 'Amazon S3 bucket name for dumps'
  on :dump_profile=, 'Backup profile to use machine type'
  on :machine_name=, 'Machine name to use in identification file'
end
class LogDump

  def initialize(machine_type)
   @log_details = LOG_CONFIG[machine_type]
   puts "instantiated logdump with machine type #{machine_type}"
  end

  # @param [Hash] dump_config
  def prepare_logs
    puts 'preparing logs for archive'
    archive_locations = []
    @log_details.each {|log_detail| archive_locations.push(process_logs(log_detail)) }
    archive_locations
  end

  def process_logs(log_info)
    log_directory    = log_info[0]
    log_patterns     = log_info[1]
    logs_to_compress = []
    FileUtils.chdir(log_directory)
    log_patterns.each do |log_pattern|
      log_list = Dir.glob("#{log_pattern}*")
      logs_to_compress.push(log_list)
    end
    compress_logs(logs_to_compress.flatten)
  end

# @param [Array] file_names
  def compress_logs(file_names)
    archive_name = "#{Dir.pwd.split('/').reject {|item| item.empty?}.join('_').downcase}.tar.gz"
    tar_args     = "-czvf #{archive_name} #{file_names.join(' ')}"
    cmd          = "tar #{tar_args}"
    run_shell_command(cmd)
    "#{Dir.pwd}/#{archive_name}" if File.exists?(archive_name)
  end

# @param [String] cmd
  def run_shell_command(cmd)
    res=`#{cmd}`
    res
  end

end
class S3Upload
  def initialize(files_to_upload,settings)
    @upload_contents = files_to_upload
    @machine_type = settings.profile
    @machine_name = settings.machine_name
    s3_details = settings
    s3_connection = Fog::Storage.new({
                                          :provider                 => 'AWS',
                                          :aws_access_key_id        => s3_details.access_key,
                                          :aws_secret_access_key    => s3_details.secret_key
                                      })
    @s3_bucket = s3_connection.directories.get(s3_details.bucket_name)
  end

  def upload_files
    puts 'uploading log archives'
    key_name = get_key_name
    @upload_contents.each do |upload|
      puts "--#{upload}\n"
      archive_name = upload.split('/').last
      file = @s3_bucket.files.new(:key => "#{key_name}/#{archive_name}")
      file.body = File.open(upload)
      file.save
    end
    write_identifier(key_name)
  end

  def write_identifier(key_name)
    hostname = @machine_name
    id = @s3_bucket.files.new(:key => "#{key_name}/#{hostname}")
    id.save
  end

  def uptime_range
    days_up    = `uptime | awk {'print$3'}`.chomp.to_i
    hours_up   = `uptime | awk {'print$5'}`.delete(',').chomp
    seconds_up = time_to_seconds(days_up,hours_up)
    birth      = Time.now - seconds_up
    "#{birth.strftime('%Y.%m.%d.%H.%M')}-#{Time.now.strftime('%Y.%m.%d.%H.%M')}"
  end

  def get_key_name
    "#{uptime_range}.#{@machine_type}"
  end

  def time_to_seconds(days,hour)
    time    = hour.split(':')
    days    = days * 86400
    hours   = time[0].to_i * 3600
    minutes = time[1].to_i * 60
    hours + minutes + days
  end


end
class Settings
  attr_reader :access_key, :secret_key, :bucket_name, :profile, :machine_name
  def initialize(options=nil,profile=nil)
    raise('Command line options or a profile name must be provided') unless options || profile
    if profile && File.exists?('s3_config.yml')
      s3_config = YAML.load_file('s3_config.yml')[ENV['RAILS_ENV']]
      profile ? s3_config['dump_profile'] = profile : raise('missing profile')
    elsif valid_options?(options)
      s3_config = options.to_hash
    else
      valid_options?(options,true)
    end
    @access_key = s3_config['access_key']
    @secret_key = s3_config['secret_key']
    @bucket_name = s3_config['bucket_name']
    @profile = s3_config['dump_profile']
    @machine_name = s3_config['machine_name'].split(' ').join('-') || `hostname`.chomp
  end

  def valid_options?(options,return_missing=nil)
    return false if options.nil?
    options_hash = options.to_hash
    missing_values = options_hash.keys.select {|key| options_hash[key].nil?}
    raise(ArgumentError, "The following arguments do not have values #{missing_values}, please see usage for proper commands") if return_missing
    if missing_values.count != 0
      false
    else
      true
    end
  end
end

if options.dump_profile? && !options.access_key?
  settings = Settings.new(nil,options['dump_profile'])
else
  settings = Settings.new(options)
end
log_dump = LogDump.new(settings.profile)
uploader = S3Upload.new(log_dump.prepare_logs,settings)
uploader.upload_files


