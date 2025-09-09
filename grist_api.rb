require 'net/http'
require 'uri'
require 'json'

class GristApi
  def initialize(api_url:, api_key:, document_id:)
    @api_url = api_url
    @api_key = api_key
    @document_id = document_id
  end

  def tables
    response = make_request(:get, "/docs/#{@document_id}/tables")
    response['tables']
  end

  def columns(table_id)
    response = make_request(:get, "/docs/#{@document_id}/tables/#{table_id}/columns")
    response['columns']
  end

  def records(table_id)
    response = make_request(:get, "/docs/#{@document_id}/tables/#{table_id}/records")
    response['records']
  end

  private

  def make_request(verb, endpoint, body = nil)
    uri = URI("#{@api_url}#{endpoint}")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    
    # Create request using dynamic method call
    request_class = Net::HTTP.const_get(verb.to_s.capitalize)
    request = request_class.new(uri)
    
    request['Authorization'] = "Bearer #{@api_key}"
    request['Content-Type'] = 'application/json'
    
    # Add body for POST, PUT, PATCH requests
    if body && [:post, :put, :patch].include?(verb)
      request.body = body.to_json
    end
    
    response = http.request(request)
    
    if response.code == '200' || response.code == '201'
      JSON.parse(response.body)
    else
      raise "Failed to #{verb.upcase} #{endpoint}: #{response.code} - #{response.body}"
    end
  end
end
