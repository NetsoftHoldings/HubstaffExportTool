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
require 'json'
require 'pp'

class HubstaffExport
  VERSION = '0.0.1'

  attr_reader :options

  def initialize(arguments)
    @arguments = arguments
    # Set defaults
    @options = OpenStruct.new
    @options.verbose = false
    @api_url = 'https://api.hubstaff.com/v1/'
  end

  # Parse options, check arguments, then process the command
  def run
    # puts arguments_valid?
    if parsed_options? && arguments_valid?
      puts "Start at #{DateTime.now}\n" if @options.verbose

      output_options if @options.verbose # [Optional]

      process_command

      puts "\nFinished at #{DateTime.now}" if @options.verbose
    else
      output_usage
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
        opts.on('-s', '--starts_on STARTS_ON', 'start date to pick the screens')         {|starts_on| @options.starts_on = starts_on}
        opts.on('-f', '--ends_on ENDS_ON', 'end date to pick screens')                   {|ends_on| @options.ends_on = ends_on }
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
        puts 'unknown command'; exit 0
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
      puts 'there was a timout'; exit 0
    end

    def parse_response(response)
      if response.is_a?(Net::HTTPOK) || response.is_a?(Net::HTTPCreated)
        return JSON.parse(response.body)
      elsif response.is_a?(Net::HTTPNotFound)
        puts 'page not found'; exit 0
      elsif response.is_a?(Net::HTTPUnauthorized)
        puts 'not authorized request'; exit 0
      elsif response.is_a?(Net::HTTPBadRequest)
        puts 'bad request'; exit 0
      else
        puts 'other error'; exit 0
      end
    end

    def authentication
      puts 'doing authentication' if @options.verbose
      response = post("#{@api_url}/auth", {email: @options.email, password: @options.password})

      file = File.new('hubstaff-client.cfg', "w")
      File.open(file, 'w') { |file| file.write({token: response["user"]["auth_token"], app_token: @options.app_token, password: @options.password, email: @options.email}.to_json) }
    end

    def client_config
      puts 'Please use authentication command first'; exit 0 unless File.exists?('hubstaff-client.cfg')
      @client_config ||= JSON.parse(File.read('hubstaff-client.cfg'))
    end

    def export_screens
      puts 'exporting screens\n' if @options.verbose

      pp client_config
    end
end

# Create and run the application
export = HubstaffExport.new(ARGV)
export.run

