require 'erb'

class Config

  attr_accessor :name
  attr_accessor :backend
  attr_accessor :server
  attr_accessor :nginx_template
  attr_accessor :host_template

  def initialize(opts)
    @name = opts[:name] ||= 'app'
    @nginx = opts[:nginx] ||= {
        :user => 'root',
        :worker_processes => 4
    }
    @nginx_template = opts[:nginx_template] ||= File.join(File.dirname(__FILE__), "/templates/nginx.config.erb")

    @backend = opts[:backend] ||= {
        :name => 'collector_backend',
        :healthcheck => {
            :delay => 10000,
            :timeout => 2000,
            :failcount => 2,
            :send => "'GET /private/status HTTP/1.0'"
        },
        :hosts => [
            {:name => '1.1.1.1', :opts => 'weight=2'},
            {:name => '2.2.2.2', :opts => 'weight=1'}
        ]
    }

    @server = opts[:server] ||= [
        {
            :listen => [443, 80],
            :server_name => 'data.brightcove.com',
            :ssl => {
                :certificate => '/usr/local/brightcove/analytics-collector/ext/certificate.pem',
                :certificate_key => '/usr/local/brightcove/analytics-collector/ext/certificate_key.pem',
                :ssl_session_timeout => '5m'
            },
            :locations => [
                {
                    :matcher => '/',
                    :keepalive_timeout => '75s',
                    :backend => 'collector_backend'
                }
            ]
        }
    ]
    @host_template = opts[:host_template] ||= File.join(File.dirname(__FILE__), "/templates/http.config.erb")
  end

  def nginx_config_file
    ERB.new(File.read(File.expand_path(@nginx_template))).result(binding)
  end

  def host_config_file
    ERB.new(File.read(File.expand_path(@host_template))).result(binding)
  end

  def is_same?(old_file_path)
    current_config_file = host_config_file.join("")
    if File.exists?(old_file_path)
      old_config_file = File.open(old_file_path).readlines.join("")
      #compare old file and new file
      current_config_file == old_config_file
    else
      # no old file exists
      false
    end
  end
end