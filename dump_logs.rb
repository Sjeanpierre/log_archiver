require 'fileutils'
require 'fog'

class LogDump

  def initialize(machine_type)
   @log_details = YAML.load_file('dump_config.yml')[machine_type]
  end

  # @param [Hash] dump_config
  def prepare_logs
    archive_locations = []
    @log_details.each {|log_detail| archive_locations.push(process_logs(log_detail)) }
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
  def initialize(files_to_upload)
    @upload_contents = files_to_upload
    s3_details = YAML.load_file('s3_config.yml')[RAILS_ENV]
    @s3_connection = Fog::Storage.new({
                                          :provider                 => 'AWS',
                                          :aws_access_key_id        => s3_details['access_key'],
                                          :aws_secret_access_key    => s3_details['secret_key']
                                      })
  end

  def upload_files

  end

  def uptime_range
    days_up    = `uptime | awk {'print$3'}`.chomp.to_i
    hours_up   = `uptime | awk {'print$5'}`.delete(',').chomp
    seconds_up = time_to_seconds(days_up,hours_up)
    birth      = Time.now - seconds_up
    "#{birth.strftime('%Y.%m.%d.%H.%M')}-#{Time.now.strftime('%Y.%m.%d.%H.%M')}"
  end

  def time_to_seconds(days,hour)
    time    = hour.split(':')
    days    = days * 86400
    hours   = time[0].to_i * 3600
    minutes = time[1].to_i * 60
    hours + minutes + days
  end


end

b = LogDump.new('rails_frontend')
b.prepare_logs

