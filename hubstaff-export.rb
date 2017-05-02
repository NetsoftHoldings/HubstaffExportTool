#!/usr/bin/env ruby

# == Synopsis
#   This is a simple hubstaff.com export tool for the screenshots.
#   It uses the Hubstaff API.
#
# == Examples
#   Commands to call
#     ruby hubstaff-export.rb authenticate abc345 bob@example.com MyAwesomePass
#     ruby hubstaff-export.rb export-screens 2015-07-01T00:00:00Z 2015-07-01T07:00:00Z -o 84 -i both
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
#   -p, --projects      Comma separated list of project IDs
#   -u, --users         Comma separated list of user IDs
#   -i, --image_format  What image to export (full || thumb || both)
#   -o, --organizations Comma separated list of organization IDs
#   -d, --directory     A path to the output directory (otherwise ./screens is assumed)
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
  VERSION = '0.5.0'

  attr_reader :options

  def initialize(arguments)
    @arguments = arguments
    # Set defaults
    @options = OpenStruct.new
    @options.verbose = false
    @options.image_format = 'full'
    @options.directory = 'screens'
    @options.skip_ssl_verify = false
    @api_url = 'https://api.hubstaff.com/v1'
  end

  # Parse options, check arguments, then process the command
  def run
    # puts arguments_valid?
    if parsed_options?
      puts "Start at #{DateTime.now}" if verbose?

      output_options if verbose?

      process_command

      puts "\nFinished at #{DateTime.now}" if verbose?
    else
      puts 'The options passed are not valid!'
    end
  end

  protected

    def parsed_options?
      # Specify options
      @opts_parser = OptionParser.new do |opts|
        opts.banner = "Usage: hubstaff-export COMMAND [OPTIONS]"
        opts.separator  ""
        opts.separator  "Commands"
        opts.separator  "     authenticate app_token username password"
        opts.separator  "       Authenticates and caches the tokens to 'hubstaff-client.cfg' in the current folder"
        opts.separator  "     export-screens start_time stop_time"
        opts.separator  "       Exports screenshots on a defined period."
        opts.separator  "       Screenshots are exported into a folder structure like this"
        opts.separator  "       - project - 34/user - 123/2015-07-01/123023-screen-0.jpg"
        opts.separator  "       - (123023 is the hour, minutem second of the screenshot)"
        opts.separator  "       Start and stop time must be in the ISO8601 format. e.g. YYYY-MM-DDThh:mmZ"
        opts.separator  "       where Z means that the time is in UTC or it can be a timezone offset"
        opts.separator  "       - ex.  2015-06-01T04:00Z  or 2015-06-01T00:00-0400 or 2015-06-01T05:00+0100"
        opts.separator  "       - (those all represent the same time)"
        opts.separator  ""
        opts.separator  "Options"

        opts.on('-v', '--version', 'version of the application')  { output_version ; exit 0 }
        opts.on('-h', '--help', 'help method to show options')    { puts opts; exit 0 }
        opts.on('-V', '--verbose', 'verbose the script calls')    { @options.verbose = true }

        opts.on('-p', '--projects PROJECTS', 'comma separated list of project IDs')  {|projects| @options.projects = projects}
        opts.on('-u', '--users USERS', 'comma separated list of user IDs')           {|users| @options.users = users}
        opts.on(nil, '--no-ssl-verify', 'disable SSL certificate validation')        {|s| @options.skip_ssl_verify = s}

        opts.on('-i', '--image_format IMAGE_EXPORT_TYPE', 'what image to export (full || thumb || both) (default is full only)') do |image_format|
          @options.image_format = image_format
        end
        opts.on('-o', '--organizations ORGANIZATIONS', 'comma separated list of organization IDs (required)') do |organizations|
          @options.organizations = organizations
        end
        opts.on('-d', '--directory DIRECTORY', 'a path to the output directory (otherwise ./screens is assumed)') do |directory|
          @options.directory = directory
        end
      end
      @opts_parser.parse!(@arguments) rescue return false
      true
    end

    def output_options
      puts "Options:\n"

      @options.marshal_dump.each do |name, val|
        puts "  #{name} = #{val}"
      end
    end

    def output_version
      puts "#{File.basename(__FILE__)} version #{VERSION}"
    end

    def process_command
      case @arguments[0]
      when 'authenticate'
        authenticate(@arguments[1], @arguments[2], @arguments[3])
      when 'export-screens'
        export_screens(@arguments[1], @arguments[2])
      when nil
        puts @opts_parser
        exit
      else
        puts @opts_parser
        fail "*** Unknown command #{@arguments[0]}"
      end
    end

    def http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE if @options.skip_ssl_verify
      http.use_ssl = true
      return http
    end

    def post(url, params)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri.request_uri)
      request['App-Token'] = client_config["app_token"]
      request.set_form_data(params)

      parse_response(http(uri).request(request))
    rescue Errno::ETIMEDOUT => ex
      fail 'there was a timout'
    end

    def get(url, params)
      uri = URI.parse(url)
      uri.query = URI.encode_www_form(params)
      request = Net::HTTP::Get.new(uri.request_uri)
      request['App-Token'] = client_config["app_token"]
      request['Auth-Token'] = client_config["auth_token"]

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
        fail 'bad request'
      elsif response.is_a?(Net::HTTPServiceUnavailable)
        fail 'timeout fetching data.'
      else
        fail "Unexpected Error: #{response}"
      end
    end

    def client_config
      unless File.exists?('hubstaff-client.cfg')
        fail 'Please use authenticat command first'
      end
      @client_config ||= JSON.parse(File.read('hubstaff-client.cfg'))
    end

    def authenticate(app_token, email, password)
      puts 'Doing authentication' if verbose?
      fail 'Email & password are required' unless email && password
      File.open('hubstaff-client.cfg', 'w') { |file| file.write({app_token: app_token}.to_json) }

      response = post("#{@api_url}/auth", {email: email, password: password})

      File.open('hubstaff-client.cfg', 'w') { |file| file.write({auth_token: response["user"]["auth_token"], app_token: app_token, email: email}.to_json) }
      puts 'User authentication successful. Tokens are now catched in ./hubstaff-client.cfg'
    end

    def export_screens(start_time, stop_time)
      # raise error if the required parameters are missing
      fail 'start_time stop_time are required' unless start_time && stop_time
      fail 'an organization filter is required (-o)' if @options.organizations.nil?

      start_time = DateTime.iso8601(start_time)
      stop_time = DateTime.iso8601(stop_time)

      # display a simple message of the number of screenshots available
      # DateTime + 1 means increment by one day
      while start_time < stop_time
        stop = [start_time + 1, stop_time].min
        puts "Saving screenshots for #{start_time} to #{stop}"
        export_screens_for_range(start_time, stop)
        start_time = start_time + 1
      end
    end

    def export_screens_for_range(start_time, stop_time)
      offset = 0
      extra = case @options.image_format
                when 'both'
                  'with full and thumbs'
                when 'full'
                  'with just full'
                when 'thumb'
                  'with just thumbs'
                end
      loop do
        # make the get request to get screenshots
        arguments = { start_time:     start_time.iso8601,
                      stop_time:      stop_time.iso8601,
                      organizations:  @options.organizations,
                      users:          @options.users,
                      projects:       @options.projects,
                      offset:         offset
                    }.compact
        data  = get("#{@api_url}/screenshots", arguments)

        num_fetched = data['screenshots'].count
        break unless num_fetched > 0

        puts "> Exporting a batch of #{num_fetched} screenshots #{extra}."

        data['screenshots'].each do |screenshot|
          begin
            save_files(screenshot, @options.image_format)
            print '.'
          rescue
            puts 'x'
          end
        end

        puts

        offset += num_fetched
      end
    end

    def directory_for_screenshot(screenshot)
      File.join(@options.directory, "project - #{screenshot['project_id']}", "user - #{screenshot['user_id']}", DateTime.iso8601(screenshot['time_slot']).strftime('%Y-%m-%d'))
    end

    def check_directory(screenshot)
      directory_path = directory_for_screenshot(screenshot)
      FileUtils::mkdir_p(directory_path) unless File.directory?(directory_path)
    end

    def get_screenshot_details(screenshot, thumb=false)
      # create the directory path where we'll save all the screenshots
      check_directory(screenshot)

      file_name = "#{DateTime.iso8601(screenshot['recorded_at']).strftime('%I_%M_%S')}-screen-#{screenshot['screen']}#{thumb ? '_thumb' : ''}.jpg"
      file_path = File.join(directory_for_screenshot(screenshot), file_name)

      file_path
    end

    def save_files(screenshot, image_format)
      if image_format=='both'
        save_full(screenshot)
        save_thumb(screenshot)
      elsif image_format=='full'
        save_full(screenshot)
      elsif image_format=='thumb'
        save_thumb(screenshot)
      end
    end

    def save_full(screenshot)
      url_remote        = screenshot['url']
      file_path = get_screenshot_details(screenshot)
      download_file(url_remote, file_path)
    end

    def save_thumb(screenshot)
      thumb_url_remote  = screenshot['url'].gsub /\.[^\.]*$/, "_thumb\\0"
      thumb_file_path = get_screenshot_details(screenshot, true)
      download_file(thumb_url_remote, thumb_file_path)
    end

    def download_file(url, file_path)
      uri = URI(url)
      # Save screenshots provided
      Net::HTTP.start(uri.host) do |http|
        resp = http.get(uri.path)

        open(file_path, "wb") do |file|
          file.write(resp.body)
        end
      end
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

