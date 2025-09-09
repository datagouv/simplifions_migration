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
    uri = URI("#{@api_url}/docs/#{@document_id}/tables")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Content-Type'] = 'application/json'
    
    response = http.request(request)
    
    if response.code == '200'
      JSON.parse(response.body)['tables'] || []
    else
      raise "Failed to fetch tables: #{response.code} - #{response.body}"
    end
  end
end
