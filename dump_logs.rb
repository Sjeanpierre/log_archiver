require 'fileutils'
require 'fog'

S3_CONFIG = YAML.load_file('s3_config.yml')
LOG_CONFIG = YAML.load_file('dump_config.yml')

class LogDump

  def initialize(machine_type)
   @log_details = LOG_CONFIG[machine_type]
  end

  # @param [Hash] dump_config
  def prepare_logs
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
  def initialize(files_to_upload,upload_id)
    @upload_contents = files_to_upload
    @machine_type = upload_id
    s3_details = S3_CONFIG[ENV['RAILS_ENV']]
    s3_connection = Fog::Storage.new({
                                          :provider                 => 'AWS',
                                          :aws_access_key_id        => s3_details['access_key'],
                                          :aws_secret_access_key    => s3_details['secret_key']
                                      })
    @s3_bucket = s3_connection.directories.get(s3_details['bucket_name'])
  end

  def upload_files
    key_name = get_key_name
    @upload_contents.each do |upload|
      archive_name = upload.split('/').last
      log = @s3_bucket.files.new(:key => "#{key_name}/#{archive_name}")
      log.body = File.open(upload)
      log.save
    end
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
type = 'rails_frontend'
b = LogDump.new(type)
uploader = S3Upload.new(b.prepare_logs,type)
uploader.upload_files


