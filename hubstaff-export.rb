#!/usr/bin/env ruby
# frozen_string_literal: true

# == Synopsis
#   This is a simple hubstaff.com export tool for the screenshots.
#   It uses the Hubstaff API.
#
# == Examples
#   Commands to call
#     ruby hubstaff-export.rb token PErsonalAccessrefreshToken
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
#   -o, --organization  The organization ID to perform against
#   -d, --directory     A path to the output directory (otherwise ./screens is assumed)
#
# == Author
#   Chocksy - @Hubstaff

require 'optparse'
require 'ostruct'
require 'date'
require 'net/http'
require 'fileutils'
require 'forwardable'
require 'base64'
require 'json'
require 'pp'

# a network error occurred
class NetworkError < StandardError; end

# an error from a command
class CommandError < StandardError; end

# an error when there is no valid token
class NoTokenError < StandardError; end

# Simple network wrapper around Net::HTTP
class HTTPClient
  # @param skip_ssl_verify [Boolean]
  def initialize(skip_ssl_verify: false)
    @skip_ssl_verify = skip_ssl_verify
  end

  def post(url, params: {}, headers: nil)
    uri     = URI.parse(url)
    request = Net::HTTP::Post.new(uri.request_uri, headers)

    request.set_form_data(params)

    parse_response(http(uri).request(request))
  rescue Errno::ETIMEDOUT
    raise NetworkError, 'there was a timout'
  end

  def post_json(url, params: {}, headers: nil)
    uri                  = url.is_a?(URI) ? url : URI.parse(url)
    request              = Net::HTTP::Post.new(uri.request_uri, headers)
    request.content_type = 'application/json'
    request.body         = params.to_json

    parse_response(http(uri).request(request))
  rescue Errno::ETIMEDOUT
    raise NetworkError, 'there was a timout'
  end

  def get(url, params: {}, headers: nil)
    uri       = url.is_a?(URI) ? url : URI.parse(url)
    uri.query = URI.encode_www_form(params)
    request   = Net::HTTP::Get.new(uri.request_uri, headers)

    parse_response(http(uri).request(request))
  rescue Errno::ETIMEDOUT
    raise NetworkError, 'there was a timout'
  end

  private

  def parse_response(response)
    case response
    when Net::HTTPOK, Net::HTTPCreated
      JSON.parse(response.body, symbolize_names: true)
    when Net::HTTPNotFound
      raise NetworkError, 'page not found'
    when Net::HTTPUnauthorized
      raise NetworkError, 'not authorized request'
    when Net::HTTPBadRequest
      raise NetworkError, 'bad request'
    when Net::HTTPTooManyRequests
      raise NetworkError, 'rate limit reached'
    when Net::HTTPServiceUnavailable
      raise NetworkError, 'timeout fetching data.'
    else
      raise NetworkError, "Unexpected Error: #{response}"
    end
  end

  def http(uri)
    http             = Net::HTTP.new(uri.host, uri.port)
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE if @skip_ssl_verify
    http.use_ssl     = true
    http
  end
end

# Class to manage communicating with the auth server
class AuthClient
  # @param config_store [ConfigStore]
  # @param skip_ssl_verify [Boolean]
  def initialize(openid_issuer, config_store, skip_ssl_verify: false)
    @config_store = config_store
    @http_client  = HTTPClient.new(skip_ssl_verify: skip_ssl_verify)

    if @config_store[:openid_issuer] != openid_issuer
      @config_store[:openid_issuer] = openid_issuer
      @config_store.delete(:openid_cache)
      @config_store.delete(:openid_cache_expire)
      @config_store.save!
    end

    load_check
  end

  def token_endpoint
    discovery_info[:token_endpoint]
  end

  def discovery_info
    @config_store[:openid_cache]
  end

  def refresh_token=(refresh_token)
    do_refresh(refresh_token)
  end

  def refresh_token!
    do_refresh(@config_store.dig(:token, :refresh_token))
  end

  private

  def load_check
    expire = @config_store[:openid_cache_expire]
    return unless expire.nil? || expire < Time.now.to_i

    @config_store[:openid_cache]        = @http_client.get(@config_store[:openid_issuer])
    @config_store[:openid_cache_expire] = Time.now.to_i + (7 * 24 * 60 * 60) # 1 week
    @config_store.save!
  end

  def do_refresh(refresh_token)
    params = {
      grant_type:    'refresh_token',
      refresh_token: refresh_token,
    }

    response = @http_client.post(token_endpoint, params: params)

    @config_store[:token] = {
      refresh_token: response[:refresh_token],
      access_token:  response[:access_token],
    }
    @config_store.save!
  end
end

# Manage configuration persistence
class ConfigStore
  attr_reader :config_file

  def initialize(config_file)
    @config_file = config_file
    @config      = {}

    load
  end

  def load
    return unless File.exist?(config_file)

    @config = JSON.parse(File.read(config_file), symbolize_names: true)
  rescue
    @config = {}
  end

  def save!
    File.open(config_file, 'w') do |file|
      file.write(JSON.generate(@config, {indent: '  ', object_nl: "\n", array_nl: "\n"}))
    end
  end

  def [](key)
    @config[key]
  end

  def []=(key, value)
    @config[key] = value
  end

  def delete(key)
    @config.delete(key)
  end

  def dig(*keys)
    @config.dig(*keys)
  end
end

# Class to manage the token and triggering automatic refeshes
class TokenStore
  # @param auth_client [AuthClient]
  # @param config_store [ConfigStore]
  def initialize(auth_client, config_store)
    @auth_client  = auth_client
    @config_store = config_store
  end

  # @return [Hash]
  def headers
    {
      Authorization: "Bearer #{access_token}",
    }
  end

  # @return [String]
  def access_token
    token_data = decode_token(@config_store.dig(:token, :access_token))
    @auth_client.refresh_token! if token_data[:exp] < (Time.now.to_i + 300)

    raise NoTokenError, "No access token" if @config_store.dig(:token, :access_token).nil?

    @config_store.dig(:token, :access_token)
  end

  def decode_token(token)
    return {exp: 0} if token.nil?

    parts = token.split('.')
    JSON.parse(Base64.decode64(parts[1]), symbolize_names: true)
  rescue
    {exp: 0}
  end
end

# Simple Hubstaff API Wrapper
class APIClient
  # @param base_url [String]
  # @param token_store [TokenStore]
  # @param skip_ssl_verify [Boolean]
  def initialize(base_url, token_store, skip_ssl_verify: false)
    @http_client = HTTPClient.new(skip_ssl_verify: skip_ssl_verify)

    @base_url    = URI.parse(base_url)
    @token_store = token_store
  end

  def post(path, params)
    @http_client.post_json(@base_url.merge(path), params: params, headers: @token_store.headers)
  end

  def get(path, params)
    @http_client.get(@base_url.merge(path), params: params, headers: @token_store.headers)
  end
end

# Main class for the export tool
class HubstaffExport
  VERSION = '0.6.0'

  CONFIG_FILE = 'hubstaff-client.cfg'

  DISCOVERY_URL = 'https://account.hubstaff.com/.well-known/openid-configuration'

  API_URL = 'https://api.hubstaff.com/v2/'

  attr_reader :options
  attr_reader :config_store
  attr_reader :auth_client
  attr_reader :token_store
  attr_reader :api_client

  def initialize(arguments)
    @arguments = arguments
    # Set defaults
    @options                 = OpenStruct.new
    @options.verbose         = false
    @options.image_format    = 'full'
    @options.directory       = 'screens'
    @options.skip_ssl_verify = false

    @config_store = ConfigStore.new(CONFIG_FILE)
    @auth_client  = AuthClient.new(DISCOVERY_URL, @config_store)
    @token_store  = TokenStore.new(@auth_client, @config_store)
    @api_client   = APIClient.new(API_URL, @token_store, skip_ssl_verify: options.skip_ssl_verify)
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

  def verbose?
    options.verbose
  end

  protected

  def parsed_options?
    # Specify options
    @opts_parser = OptionParser.new do |opts|
      opts.banner = 'Usage: hubstaff-export COMMAND [OPTIONS]'
      opts.separator ''
      opts.separator <<~TEXT
        Commands:
          token personal_access_refresh_token
            Stores the seed refresh token from a personal access token to '#{CONFIG_FILE}' in the current folder
          export-screens start_time stop_time
            Exports screenshots on a defined period.
            Screenshots are exported into a folder structure like this
             - project - 34/user - 123/2015-07-01/123023-screen-0.jpg
             - (123023 is the hour, minutem second of the screenshot)
            Start and stop time must be in the ISO8601 format. e.g. YYYY-MM-DDThh:mmZ
            where Z means that the time is in UTC or it can be a timezone offset
             - ex.  2015-06-01T04:00Z  or 2015-06-01T00:00-0400 or 2015-06-01T05:00+0100
             - (those all represent the same time)

        Options:
      TEXT

      opts.on('-v', '--version', 'version of the application') do
        output_version
        exit 0
      end
      opts.on('-h', '--help', 'help method to show options') do
        puts opts
        exit 0
      end
      opts.on('-V', '--verbose', 'verbose the script calls') { options.verbose = true }

      opts.on('-p', '--projects PROJECTS', 'comma separated list of project IDs') do |projects|
        options.projects = projects
      end
      opts.on('-u', '--users USERS', 'comma separated list of user IDs') { |users| options.users = users }
      opts.on(nil, '--no-ssl-verify', 'disable SSL certificate validation') { |s| options.skip_ssl_verify = s }

      opts.on('-i', '--image_format IMAGE_EXPORT_TYPE',
              'what image to export (full || thumb || both) (default is full only)') do |image_format|
        options.image_format = image_format
      end
      opts.on('-o', '--organizations ORGANIZATION', 'The organization to fetch data for (required)') do |organization|
        options.organization = organization
      end
      opts.on('-d', '--directory DIRECTORY',
              'a path to the output directory (otherwise ./screens is assumed)') do |directory|
        options.directory = directory
      end
    end
    begin
      @opts_parser.parse!(@arguments)
    rescue StandardError
      return false
    end
    true
  end

  def output_options
    puts "Options:\n"

    options.marshal_dump.each do |name, val|
      puts "  #{name} = #{val}"
    end
  end

  def output_version
    puts "#{File.basename(__FILE__)} version #{VERSION}"
  end

  def process_command
    case @arguments[0]
    when 'token'
      TokenCommand.new(self, @arguments[1..]).run
    when 'export-screens'
      ExportScreensCommand.new(self, @arguments[1..]).run
    when nil
      puts @opts_parser
      exit
    else
      puts @opts_parser
      raise CommandError, "*** Unknown command #{@arguments[0]}"
    end
  rescue => ex
    puts ex.message
    exit(1)
  end
end

# Base command class
class BaseCommand
  attr_reader :app, :arguments

  extend Forwardable

  # @param app [HubstaffExport]
  # @param arguments [Array<String>]
  def initialize(app, arguments)
    @app       = app
    @arguments = arguments
  end

  def run
    raise NotImplementedError
  end

  def_delegators :app, :verbose?, :options, :api_client
end

# Token command that verifies and stores the PAT.
class TokenCommand < BaseCommand
  def run
    refresh_token = arguments[0]

    puts 'Verifying token' if verbose?
    raise CommandError, 'Refresh token is required' unless refresh_token

    app.auth_client.refresh_token = refresh_token

    puts 'Token verification successful. Tokens are now cached in ./' + app.config_store.config_file
  end
end

# Export screens command to export screenshots
class ExportScreensCommand < BaseCommand
  def run
    start_time, stop_time = arguments

    # raise error if the required parameters are missing
    raise CommandError, 'start_time stop_time are required' unless start_time && stop_time
    raise CommandError, 'an organization id is required (-o)' if options.organization.nil?

    start_time = DateTime.iso8601(start_time)
    stop_time  = DateTime.iso8601(stop_time)

    # display a simple message of the number of screenshots available
    # DateTime + 1 means increment by one day
    while start_time < stop_time
      stop = [start_time + 1, stop_time].min
      puts "Saving screenshots for #{start_time} to #{stop}"
      export_screens_for_range(start_time, stop)
      start_time += 1
    end
  end

  FORMAT_MESSAGE = {
    both:  'with full and thumbs',
    full:  'with just full',
    thumb: 'with just thumbs',
  }.freeze

  def export_screens_for_range(start_time, stop_time)
    offset = nil
    extra  = FORMAT_MESSAGE.fetch(options.image_format.to_sym, '')
    loop do
      # make the get request to get screenshots
      params = {
        'time_slot[start]': start_time.iso8601,
        'time_slot[stop]':  stop_time.iso8601,
        user_ids:           options.users,
        project_ids:        options.projects,
        page_start_id:      offset,
        page_limit:         500,
      }.compact

      data = api_client.get("organizations/#{options.organization}/screenshots", params)

      num_fetched = data[:screenshots].count
      break unless num_fetched.positive?

      puts "> Exporting a batch of #{num_fetched} screenshots #{extra}."

      data[:screenshots].each do |screenshot|
        save_files(screenshot, options.image_format)
        print '.'
      rescue StandardError
        print 'x'
      end

      puts

      offset = data.dig(:pagination, :next_page_start_id)
      break if offset.nil?
    end
  end

  def directory_for_screenshot(screenshot)
    File.join(
      options.directory,
      "project - #{screenshot[:project_id]}", "user - #{screenshot[:user_id]}",
      DateTime.iso8601(screenshot[:time_slot]).strftime('%Y-%m-%d')
    )
  end

  def check_directory(screenshot)
    directory_path = directory_for_screenshot(screenshot)
    FileUtils.mkdir_p(directory_path) unless File.directory?(directory_path)
  end

  def get_screenshot_details(screenshot, thumb: false)
    # create the directory path where we'll save all the screenshots
    check_directory(screenshot)

    time_stamp = DateTime.iso8601(screenshot[:recorded_at]).strftime('%I_%M_%S')
    file_name  = "#{time_stamp}-screen-#{screenshot[:screen]}#{thumb ? '_thumb' : ''}.jpg"
    File.join(directory_for_screenshot(screenshot), file_name)
  end

  def save_files(screenshot, image_format)
    case image_format.to_sym
    when :both
      save_full(screenshot)
      save_thumb(screenshot)
    when :full
      save_full(screenshot)
    when :thumb
      save_thumb(screenshot)
    end
  end

  def save_full(screenshot)
    file_path = get_screenshot_details(screenshot)
    download_file(screenshot[:full_url], file_path)
  end

  def save_thumb(screenshot)
    thumb_file_path = get_screenshot_details(screenshot, thumb: true)
    download_file(screenshot['thumb_url'], thumb_file_path)
  end

  def download_file(url, file_path)
    uri = URI(url)
    # Save screenshots provided
    Net::HTTP.start(uri.host) do |http|
      resp = http.get(uri.path)

      File.open(file_path, 'wb') do |file|
        file.write(resp.body)
      end
    end
  end
end

# Create and run the application
export = HubstaffExport.new(ARGV)
export.run
