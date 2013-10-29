require 'aws-sdk'
require 'json'
class S3Store

  def initialize(prefix, bucket)
    s3 = AWS::S3.new
    @bucket = s3.buckets[bucket]
    @bucket = s3.buckets.create(bucket) unless @bucket.exists?
    @prefix = prefix
  end

  def get(key)
    JSON.parse(getObject(prefixedKey(key)) || {})
  end

  def put(key, data)
    object = @bucket.objects[prefixedKey(key)]
    object.write(data)
  end

  def delete(key)
    object = @bucket.objects[prefixedKey(key)]
    object.delete
  end


  def list
    @bucket.as_tree(:prefix => @prefix).children.select(&:leaf?).collect(&:key)
  end

  private
  def prefixedKey(key)
    "#{@prefix}/#{key}.json"
  end

  private
  def getObject(key)
    object = @bucket.objects[key]
    (object.exists? ? object.read : nil)
  end

end