#!/usr/bin/env ruby

# == Synopsis
#   This is a simple hubstaff.com export tool for the screenshots.
#   It uses the Hubstaff API.
#
# == Examples
#   Commands to call
#     ruby hubstaff-export.rb authentication abc345 bob@example.com MyAwesomePass
#     ruby hubstaff-export.rb export-screens 2015-06-01T00:00Z 2015-07-01T00:00Z -o 3 -e both -d ./screens-june
#
# == Usage
#   ruby hubstaff-export.rb [action] [options]
#
#   For help use: ruby hubstaff-export.rb -h
#
# == Options
#   -h, --help          Displays help message
#   -v, --version       Display the version, then exit
#   -V, --verbose       Verbose output
#
# == Author
#   Chocksy - @Hubstaff

require 'optparse'
require 'ostruct'
require 'date'
require 'net/http'
require 'fileutils'
require 'json'
require 'pp'

class Hash
  def compact
    delete_if {|k,v| v.nil? }
  end
end

class HubstaffExport
  VERSION = '0.0.1'

  attr_reader :options

  def initialize(arguments)
    @arguments = arguments
    # Set defaults
    @options = OpenStruct.new
    @options.verbose = false
    @options.image_formats = 'full'
    @options.directory = 'screens'
    @api_url = 'https://api.hubstaff.com/v1'
  end

  # Parse options, check arguments, then process the command
  def run
    # puts arguments_valid?
    if parsed_options? && arguments_valid?
      puts "Start at #{DateTime.now}" if verbose?

      output_options if verbose?

      process_command

      puts "Finished at #{DateTime.now}" if verbose?
    else
      puts 'The options passed are not valid!'
    end
  end

  protected

    def parsed_options?
      # Specify options
      opts_parser = OptionParser.new do |opts|
        opts.banner = "Usage: hubstaff-export COMMAND [OPTIONS]"
        opts.separator  ""
        opts.separator  "Commands"
        opts.separator  "     authentication: used to authenticate and cache the password and username"
        opts.separator  "     export-screens: used to export the screenshots on a defined period"
        opts.separator  ""
        opts.separator  "Options"

        opts.on('-v', '--version', 'version of the application')  { output_version ; exit 0 }
        opts.on('-h', '--help', 'help method to show options')    { puts opts; exit 0 }
        opts.on('-V', '--verbose', 'verbose the script calls')    { @options.verbose = true }

        opts.on('-t', '--apptoken TOKEN', 'the application token in hubstaff')       {|token| @options.app_token = token}
        opts.on('-p', '--password PASSWORD', 'the password to authenticate account') {|password| @options.password = password }
        opts.on('-e', '--email EMAIL', 'the email used for authentication')          {|email| @options.email = email }
        opts.on('-s', '--start_time START_TIME', 'start date to pick the screens')   {|start_time| @options.start_time = start_time}
        opts.on('-f', '--stop_time STOP_TIME', 'end date to pick screens')           {|stop_time| @options.stop_time = stop_time }
        opts.on('-j', '--projects PROJECTS', 'comma separated list of project IDs')  {|projects| @options.projects = projects}
        opts.on('-u', '--users USERS', 'comma separated list of user IDs')           {|users| @options.users = users}

        opts.on('-i', '--images IMAGE_FORMATS', 'comma separated list of formats (full, thumb, both)') do |image_formats|
          @options.image_formats = image_formats
        end
        opts.on('-o', '--organizations ORGANIZATIONS', 'comma separated list of organization IDs') do |organizations|
          @options.organizations = organizations
        end
        opts.on('-d', '--directory DIRECTORY', 'a path to the output directory (otherwise ./screens is assumed)') do |directory|
          @options.directory = directory
        end
      end
      opts_parser.parse!(@arguments) rescue return false
      true
    end

    def output_options
      puts "Options:\n"

      @options.marshal_dump.each do |name, val|
        puts "  #{name} = #{val}"
      end
    end

    # True if required arguments were provided
    def arguments_valid?
      # puts @arguments.length
      # TO DO - implement your real logic here
      # true if @arguments.length == 1
      true
    end

    def output_version
      puts "#{File.basename(__FILE__)} version #{VERSION}"
    end

    def process_command
      case ARGV[0]
      when 'authentication'
        authentication
      when 'export-screens'
        export_screens
      else
        fail 'unknown command'
      end
    end

    def http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      return http
    end

    def post(url, params)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri.request_uri)
      request['app_token'] = @options.app_token
      request.set_form_data(params)

      parse_response(http(uri).request(request))
    rescue Errno::ETIMEDOUT => ex
      fail 'there was a timout'
    end

    def get(url, params)
      uri = URI.parse(url)
      uri.query = URI.encode_www_form(params)
      request = Net::HTTP::Get.new(uri.request_uri)
      request['app_token'] = client_config["app_token"]
      request['auth_token'] = client_config["auth_token"]

      parse_response(http(uri).request(request))
    rescue Errno::ETIMEDOUT => ex
      fail 'there was a timout'
    end

    def parse_response(response)
      if response.is_a?(Net::HTTPOK) || response.is_a?(Net::HTTPCreated)
        return JSON.parse(response.body)
      elsif response.is_a?(Net::HTTPNotFound)
        fail 'page not found'
      elsif response.is_a?(Net::HTTPUnauthorized)
        fail 'not authorized request'
      elsif response.is_a?(Net::HTTPBadRequest)
        puts response.body
        fail 'bad request'
      else
        fail 'other error'
      end
    end

    def client_config
      unless File.exists?('hubstaff-client.cfg')
        puts 'Please use authentication command first'; exit 0
      end
      @client_config ||= JSON.parse(File.read('hubstaff-client.cfg'))
    end

    def authentication
      puts 'doing authentication' if verbose?
      fail 'email & password are required' unless @options.email && @options.password
      response = post("#{@api_url}/auth", {email: @options.email, password: @options.password})

      file = File.new('hubstaff-client.cfg', "w")
      File.open(file, 'w') { |file| file.write({auth_token: response["user"]["auth_token"], app_token: @options.app_token, password: @options.password, email: @options.email}.to_json) }
    end

    def export_screens
      puts 'Exporting screens' if verbose?
      # raise error if the required parameters are missing
      fail 'start_time, stop_time & organizations are required' unless @options.start_time && @options.stop_time && @options.organizations
      # make the get request to get screenshots
      arguments = { start_time:     @options.start_time,
                    stop_time:      @options.stop_time,
                    organizations:  @options.organizations,
                    users:          @options.users,
                    projects:       @options.projects
                  }.compact
      response  = get("#{@api_url}/screenshots", arguments)
      fail 'there are no screenshots' unless response

      # display a simple message of the number of screenshots available
      puts 'Saving screenshots:'
      puts "    total number of screenshots #{response['screenshots'].count}"

      response['screenshots'].map do |screenshot|
        # create the directory path where we'll save all the screenshots
        uri = URI(screenshot['url'])
        directory_path = "#{@options.directory}/project - #{screenshot['project_id']}/user - #{screenshot['user_id']}/#{Date.parse(screenshot['time_slot']).strftime('%Y-%m-%d')}"
        FileUtils::mkdir_p(directory_path) unless File.directory?(directory_path)
        # Save screenshots provided and output some feedback
        Net::HTTP.start(uri.host) do |http|
          print '.'

          resp = http.get(uri.path)
          file_name = "#{DateTime.parse(screenshot['time_slot']).strftime('%I_%M')}-#{screenshot['screen']}.jpg"
          file_path = File.join(@options.directory, "project - #{screenshot['project_id']}", "user - #{screenshot['user_id']}", Date.parse(screenshot['time_slot']).strftime('%Y-%m-%d'), file_name)

          open(file_path, "wb") do |file|
            file.write(resp.body)
          end
        end
      end
      puts ''
      puts "Done."
    end

    def fail(message)
      puts message
      exit 0
    end

    def verbose?
      @options.verbose
    end
end

# Create and run the application
export = HubstaffExport.new(ARGV)
export.run

