#!/usr/bin/env ruby
#
# Check graphite values
# ===
#
# This plugin checks values within graphite

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'
require 'json'
require 'open-uri'

class CheckGraphiteData < Sensu::Plugin::Check::CLI

  option :target,
    :description => 'Graphite data target',
    :short => '-t TARGET',
    :long => '--target TARGET'

  option :server,
    :description => 'Server host and port',
    :short => '-s SERVER:PORT',
    :long => '--server SERVER:PORT'

  option :warning,
    :description => 'Generate warning if given value exceeds received value',
    :short => '-w VALUE',
    :long => '--warn VALUE',
    :proc => proc{|arg| arg.to_f }

  option :critical,
    :description => 'Generate critical if given value exceeds received value',
    :short => '-c VALUE',
    :long => '--critical VALUE',
    :proc => proc{|arg| arg.to_f }

  option :reset_on_change,
    :description => 'Send OK if value has beneficially changed on any values within END-INTERVAL to END',
    :short => '-r INTERVAL',
    :long => '--reset INTERVAL',
    :proc => proc{|arg| arg.to_i}

  option :name,
    :description => 'Name used in responses',
    :short => '-n NAME',
    :long => '--name NAME'

  option :allowed_graphite_age,
    :description => 'Allowed number of seconds since last data update (default: 60 seconds)',
    :short => '-a SECONDS',
    :long => '--age SECONDS',
    :proc => proc{|arg| arg.to_i }

  option :hostname_sub,
    :description => 'Character used to replace periods (.) in hostname (default: _)',
    :short => '-s CHARACTER',
    :long => '--host-sub CHARACTER'

  option :comparator,
    :description => "Comparison to use when checking values. default(: gt) {gt|lt}",
    :short => '-C COMPARISON',
    :long  => '--comparison COMPARISON',
    :proc => proc { |arg| {'gt' => :>, 'lt' => :<}[arg] },
    :default => :>

  option :timespan,
    :description => "Run check over the last MINUTES minutes of data. default(: 5)",
    :short => '-S MINUTES',
    :long => '--timespan MINUTES',
    :proc => proc {|arg| arg.to_i},
    :default => 5

  # Run checks
  def run
    check_config || retreive_data || check_age || check(:critical) || check(:warning) || ok("#{name} value okay")
  end

  # name used in responses
  def name
    base = config[:name] || "graphite check"
    @formatted ? "#{base} (#{@formatted})" : base
  end

  # check we have required configuration
  def check_config
    [:server, :target].detect do |key|
      unless(config[key])
        unknown "No graphite #{key} provided"
      end
    end

    unless config[:comparator].is_a?(Symbol)
      unknown "Unknown comparator #{config[:comparator]}. Valid options: {gt, lt}."
    end
  end

  # Check the age of the data being processed
  def check_age
    if((Time.now.to_i - @end) > (config[:allowed_graphite_age] || 60))
      critical "Graphite data age is past allowed threshold (#{config[:allowed_graphite_age] || 60} seconds)"
    end
  end

  # grab data from graphite
  def retreive_data
    metrics_after = -(config[:timespan] + 1)

    uri = "http://#{config[:server]}/render?format=json&target=#{formatted_target}&from=#{metrics_after}min"

    unless(@raw_data)
      begin
        handle = open(uri)
        @raw_data = JSON.parse(handle.gets).first
        @raw_data['datapoints'].delete(@raw_data['datapoints'].last) if @raw_data['datapoints'].last.first.nil?
        @data = @raw_data['datapoints'].map(&:first)

        @start = @raw_data['datapoints'].first.last
        @end = @raw_data['datapoints'].last.last
        @step = ((@end - @start) / @raw_data['datapoints'].size.to_f).ceil

        @data.map! { |val| val || 0 }
        nil
      rescue OpenURI::HTTPError
        critical "Failed to connect to graphite server"
      rescue NoMethodError
        critical "No data for time period and/or target"
      end
    end
  end

  # type:: :warning or :critical
  # Return alert if required
  def check(type)
    cmp = config[:comparator]
    if(config[type])
      if(@data.last.send(cmp, config[type]) && !changed?(cmp))
        send(type, "#{name} has passed #{type} threshold. Values: #{pretty_data}.")
      end
    end
  end

  def changed?(op)
    cfg = config[:reset_on_change]

    if(cfg)
      slice = @data.slice(@data.size - cfg, @data.size)
      val = slice.shift until slice.empty? || val.to_f.send(op, slice.first)
      !slice.empty?
    else
      false
    end
  end

  # Returns pretty-formatted data
  def pretty_data
    data_sequence = @data.join(', ')
    "[%s]" % data_sequence
  end

  # Returns formatted target with hostname replacing any $ characters
  def formatted_target
    if(config[:target].include?('$'))
      require 'socket'
      @formatted = Socket.gethostbyname(Socket.gethostname).first.gsub('.', config[:hostname_sub] || '_')
      config[:target].gsub('$', @formatted)
    else
      config[:target]
    end
  end

end
