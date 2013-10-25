require 'nginx/autoscale/version'
require 'thor'
require 'aws-sdk'
require 'net/http'
require 'securerandom'

module Nginx
  module Autoscale

    class CLI < Thor

      desc 'update <options>', 'run the nginx manager'
      option :access_key,                         :banner => 'AWS access key'
      option :secret_key,                         :banner => 'AWS secret key'
      option :bucket,                             :banner => 'S3 bucket containing all the configurations'
      option :prefix,                             :banner => 'S3 prefix to watch'
      option :elastic_ip,                         :banner => 'AWS Elastic IP to watch'
      option :lb_health_path, :required => false, :banner => 'Healthcheck path for the loadbalancer', :default => '/ping'
      option :lb_health_port, :required => false, :banner => 'Healthcheck port for the loadbalancer', :default => '12198'
      def update(access_key, secret_key, bucket, prefix, elastic_ip, lb_health_path, lb_health_port)
        Main.new({:access_key => access_key, :secret_key => secret_key,
                  :bucket => bucket, :prefix => prefix, :elastic_ip => elastic_ip,
                  :lb_health_path => lb_health_path, :lb_health_port => lb_health_port}).run
      end

      desc 'install', 'install nginx with all the needed modules'
      def install
        `apt-get -y install libpcre3-dev libssl-dev`
        `adduser --system --no-create-home --disabled-login --disabled-password --group nginx`
        Dir.chdir('/tmp') do
          puts 'download nginx'
          `wget http://nginx.org/download/nginx-1.2.6.tar.gz`

          puts 'extracting nginx'
          `tar -xzvf nginx-1.2.6.tar.gz`

          Dir.chdir('/tmp/nginx-1.2.6') do
            module_commands = ['--without-http_scgi_module',
                               '--without-http_uwsgi_module',
                               '--without-http_fastcgi_module',
                               '--without-http_empty_gif_module',
                               '--without-http_ssi_module',
                               '--without-http_geo_module',
                               '--without-mail_pop3_module',
                               '--without-mail_imap_module',
                               '--without-mail_smtp_module',
                               '--with-http_degradation_module',
                               '--with-http_ssl_module']

            # compile and install nginx to /opt/nginx
            puts 'configure nginx build'
            `./configure --prefix=/opt/nginx --user=nginx #{module_commands.join(' ')}`

            puts 'make and install nginx'
            `make && make install`

            puts 'configure nginx'
            `mkdir -p /opt/nginx/conf/conf.d /opt/nginx/conf/sites-available /opt/nginx/conf/sites-enabled /opt/nginx/conf/certs`
            # copy init.d startup script
            puts 'installing init.d script'
            File.cp(File.join(File.dirname(__FILE__), "/autoscale/templates/nginx.initd"), '/etc/init.d/nginx')
            `chmod a+x /etc/init.d/nginx`
          end
        end
      end
    end


    class Main
      def initialize(opts)
        AWS.config(:access_key_id => opts[:access_key],
                   :secret_access_key => opts[:secret_key])
        @ec2 = AWS::EC2.new
        @auto_scaling = AWS::AutoScaling.new
        @s3 = AWS::S3.new

        @bucket = opts[:bucket]
        @s3_prefix = opts[:prefix]
        @eip = opts[:elastic_ip]
        @config_root = opts[:config_root]
        @loadbalancer_healthcheck_path = opts[:lb_health_path]
        @loadbalancer_healthcheck_port = opts[:lb_health_port]
      end

      def run
        config_map = get_configs_from_s3
        updated = update_local_config_files(config_map)
        reload_nginx if updated > 0
      end

      def get_configs_from_s3
        objects = @s3.buckets[@bucket].objects.with_prefix(@s3_prefix)
        # read an object from S3 to a file
        config_map = {}
        objects.each do |s3object|
          key = Pathname.new(s3object.key).basename.to_s
          File.open('/tmp/nginx-config.txt', 'wb') do |file|
            s3object.read do |chunk|
              file.write(chunk)
            end
          end
          current_map = JSON.parser.new(File.open('/tmp/nginx-config.txt')).parse()
          config_map[key] = json_to_config(key, current_map)
        end
        config_map
      end

      def changed_configs(config_map)
        config_map.find_all { |k,v|
          current_conf_path = "/opt/nginx/conf/sites_available/#{k}.conf"
          !v.is_same?(current_conf_path)
        }
      end

      def update_local_config_files(config_map)
        updated = 0
        changed_configs(config_map).each do |k, v|
          conf_path = "/opt/nginx/conf/sites-available/#{k}.conf"
          symlink_path = "/opt/nginx/conf/sites-enabled/#{k}.conf"
          File.open(conf_path, 'w') do |file|
            file.write(v.host_config_file)
          end
          # enable site
          File.symlink conf_path, symlink_path
          updated += 1
        end
        updated
      end

      def asg_hosts_objects(asg_name, host_opts='max_fails=3 fail_timeout=30s', port='')
        hosts_list = []
        running_hosts_in_asg(asg_name).each do |h|
          hosts_list.push({:name => "#{h[:public_dns]}:#{port}", :host_opts => host_opts})
        end
        hosts_list
      end

      # Convert the json map to the Config object
      def json_to_config(name, json_map={})
        backend = {
            :name => name,
            :healthcheck => {
                :delay => 10000,
                :timeout => 2000,
                :failcount => 2,
                :send => "'GET #{json_map['healthcheck_path']} HTTP/1.0'"
            },
            :hosts => json_map['backends'].collect! { |p|
                        asg_hosts_objects(p['asg_name'], p['host_opts'], json_map['app_port'])
                      }.flatten!
        }

        # build server list
        listen_ports = [80]
        listen_ports.push 443 if json_map['ssl']
        matchers = json_map['endpoint_matchers'] ||= %w(/)
        locations = matchers.collect! { |m|
          {
              :matcher => m,
              :backend => name,
              :keepalive_timeout => '75s'
          }
        }
        cert_file = "/etc/nginx/config/#{SecureRandom.uuid.to_s}.crt"
        cert_key  = "/etc/nginx/config/#{SecureRandom.uuid.to_s}.key"
        if json_map['ssl_cert'] && json_map['ssl_cert_key']
          # download ssl certs and key
          File.open(cert_file, 'w') do |file|
            AWS::S3::S3Object.stream(json_map['ssl_cert'], @bucket) do |chunk|
              file.write(chunk)
            end
          end
          File.open(cert_key, 'w') do |file|
            AWS::S3::S3Object.stream(json_map['ssl_cert_key'], @bucket) do |chunk|
              file.write(chunk)
            end
          end
        end

        server = {
            :listen => listen_ports,
            :server_name => json_map['public_dns'],
            :ssl => {
                :certificate         => cert_file,
                :certificate_key     => cert_key,
                :ssl_session_timeout => '5m'
            },
            :locations => locations
        }

        Config.new({
            :name => name, # becomes the filename / app_name
            :backend => backend, # identifies the merged server set that handles the requests (gets load balanced)
            :server => server # locations that are being load balanced over the backend servers
        })
      end

      # Determine the list(with properties) of the running instances in the given autoscaling group
      # if asg_name is nil it returns nil
      def running_hosts_in_asg(asg_name)
        return nil unless asg_name
        asg = @auto_scaling.groups[asg_name]
        return nil unless asg
        # return a lost of maps having the list of running instances
        asg.auto_scaling_instances.collect { |i|
          if i.health_status != 'Healthly'
            ec2instance = i.ec2_instance.dns_name
            {
                :instance_id => ec2instance.id,
                :health_status => i.health_status,
                :public_dns => ec2instance.dns_name,
                :ip => ec2instance.ip_address
            }
          else
            nil
          end }.compact!.sort { |x,y| x.instance_id <=> y.instance_id }
      end

      # If the Elastic IP is unhealthy/unreachable, we will try to assign
      # the Elastic IP to this instance
      def try_steal_eip
        unless eip_healthy?
          # try to steal the eip
          eip_instance = @ec2.elastic_ips[@eip]
          raise "cannot find #{@eip} in list of elastic IPs" unless eip_instance
          instance = @ec2.instances[my_instance_id]
          instance.associate_elastic_ip(eip_instance)
        end
      end

      # Fetches the instance id for the current machine
      def my_instance_id
        Net::HTTP.get(URI('http://169.254.169.254/1.0/meta-data/instance-id'))
      end

      # Attempts to determine if the host with Elastic IP is reachable
      # If not reachable then returns false
      def eip_healthy?(retries=5)
        # try to ping elastic IP with eip
        uri_str = "http://#{@eip}:#{@loadbalancer_healthcheck_port}#{@loadbalancer_healthcheck_path}"
        uri = URI(uri_str)
        result = false
        retries.times.each do
          case Net::HTTP.get_response(uri)
            when Net::HTTPSuccess then
              result = true
              break
            else
              result = false
          end
        end
        result
      end

      # reload/restart nginx, uses /etc/init.d/nginx
      def reload_nginx
        if nginx_running?
          `/etc/init.d/nginx reload`
        else
          `/etc/init.d/nginx restart`
        end
      end

      # Determine if nginx is running by looking at the pidfile
      # @return [Boolean] true if nginx is running
      def nginx_running?
        if File.exists?('/var/run/nginx.pid')
          pid = File.open('/var/run/nginx.pid', 'r').readline
          begin
            Process.getpgid(pid)
            true
          rescue Errno::ESRCH
            false
          end
        else
          false
        end
      end
    end

  end
end
