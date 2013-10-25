# Nginx::Autoscale

This is a simple nginx reconfigure daemon that should be invoked using cron. This utility accepts a bunch
of parameters.

The utility watches the Elastic IP address (by pinging it). If the currently associated endpoint does not respond, the
utility would try to steal the elastic ip. At the same time, the utility also fetches the config files from S3 location
these configuration files define the backends being served. We then update (if needed) the current configuration of the
loadbalancer configuration and reload it.


Configuration files
Configuration are keyed by the filename and have the following format
```json
{
    "backends": [
        {"asg_name": "collector-production-v231", "host_opts": "weight=1"},
        {"asg_name": "collector-production-v232", "host_opts": "weight=2"}
    ],
    "healthcheck_path": "/private/status",
    "ssl": true,
    "ssl_cert": "/certs/collector.pem",
    "ssl_cert_key": "/certs/collector_key.pem",
    "public_dns": "metrics.brightcove.com",
    "app_port": 44080,
    "endpoint_matchers": ["/"]
}
```

Monitoring can be added if needed.

## Installation

Add this line to your application's Gemfile:

    gem 'nginx-autoscale'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install nginx-autoscale

## Usage

```
Usage:
  nginx-autoscale update <options>

Options:
  [--access-key=AWS access key]
  [--secret-key=AWS secret key]
  [--bucket=S3 bucket containing all the configurations]
  [--prefix=S3 prefix to watch]
  [--elastic-ip=AWS Elastic IP to watch]
  [--lb-health-path=Healthcheck path for the loadbalancer]  # Default: /ping
  [--lb-health-port=Healthcheck port for the loadbalancer]  # Default: 12198
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
