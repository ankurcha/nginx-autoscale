# coding: utf-8
$:.unshift(File.join(File.dirname(__FILE__), 'lib'))

require 'nginx/autoscale/version'

Gem::Specification.new do |spec|
  spec.name          = "nginx-autoscale"
  spec.version       = Nginx::Autoscale::VERSION
  spec.authors       = ["Ankur Chauhan"]
  spec.email         = ["achauhan@brightcove.com"]
  spec.description   = %q{Write a gem description}
  spec.summary       = %q{Write a gem summary}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"

  spec.add_dependency             "logger-colors"
  spec.add_dependency             "thor"
  spec.add_dependency             "aws-sdk"
end
