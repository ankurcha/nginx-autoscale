require 'sinatra'
require 'json-schema'
require 'aws-sdk'
require 'json'

configure :production do
  set :s3_prefix, 'production'
  set :s3_bucket, 'com.brightcove.hackweek.nginx_config'
  AWS.config(
      :access_key_id => 'access-key-id',
      :secret_access_key => 'secret-access-key')
end

configure :development do
  set :s3_prefix, 'development'
  set :s3_bucket, 'com.brightcove.hackweek.nginx_config'
  AWS.config(
      :access_key_id => 'access-key-id',
      :secret_access_key => 'secret-access-key')
end

require_relative 's3store'

s3 = S3Store.new(settings.s3_prefix, settings.s3_bucket)

def prepare_data
  unless params[:file] &&
      (tmpfile = params[:file][:tempfile]) &&
      (name = params[:file][:filename])
    return nil
  end
  {
        :name => params[:name] || name,
        :filename => name,
        :content => tmpfile
  }
end

# get the list of all backends
get '/backends' do
  content_type :json
  s3.list.to_json
end

# get a saved backend
get '/backends/:backend' do |backend|
  content_type :json
  s3.get(backend).to_json
end

# update an existing backend configuration
put '/backends/:backend' do |backend|
  content_type :json
  data = prepare_data()
  result = false
  result = s3.put(backend, data) if valid_configuration?(data) if data
  {:result => !!result}.to_json
end

# delete an existing backend configuration
delete '/backends/:backend' do |backend|
  result = s3.delete(backend)
  {:result => !!result}.to_json
end

def valid_configuration?(config)
  schema = {
      'type' => 'object',
      'properties' => {
          'app_port' => {'type' => 'integer', 'default' => 80},
          'public_dns' => {'type' => 'string'},
          'healthcheck_path' => {'type' => 'string', 'default' => '/private/status'},
          'ssl' => {'type' => 'boolean', 'default' => false},
          'ssl_cert' => {'type' => 'string'},
          'ssl_cert_key' => {'type' => 'string'},
          'endpoint_matchers' => {
              'type' => 'array',
              'items' => {'type' => 'string'}
          },
          'backends' => {
              'type' => 'array',
              'items' => {
                  'type' => [
                      {
                          'type' => 'object',
                          'properties' => {
                              'asg_name'  => {'type' => 'string'},
                              'host_opts' => {'type' => 'string'}
                          },
                          'required' => ['asg_name']
                      }
                  ],
              }
          }
      },
      'required' => ['backends', 'public_dns', 'app_port']
  }
  errors = JSON::Validator.fully_validate(schema, config, :errors_as_objects => true)
  errors ? errors : true
end