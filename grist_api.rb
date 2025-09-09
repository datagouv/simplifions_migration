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

  def records(table_id, filter: nil)
    query_params = filter ? { filter: filter.to_json } : nil
    response = make_request(:get, "/docs/#{@document_id}/tables/#{table_id}/records", query_params: query_params)
    response['records']
  end

  def record(table_id, record_id)
    response = records(table_id, filter: { id: [record_id] })
  end

  def create_record(table_id, record_data)
    create_records(table_id, [record_data])
  end

  def create_records(table_id, records_data)
    body = { records: records_data.map{ |data| fields_for_data(data) } }
    response = make_request(:post, "/docs/#{@document_id}/tables/#{table_id}/records", body)
    response['records']
  end

  def fields_for_data(data)
    { fields: data }
  end

  def create_attachment(attachment_data)
    # For file uploads, we need to use multipart form data
    uri = URI("#{@api_url}/docs/#{@document_id}/attachments")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    
    form_data = attachment_data.map do |key, value|
      [key.to_s, value, { filename: File.basename(value.path) }]
    end
    
    request.set_form(form_data, "multipart/form-data")

    response = http.request(request)
    
    if response.code == '200' || response.code == '201'
      JSON.parse(response.body)
    else
      raise "Failed to create attachment: #{response.code} - #{response.body}"
    end
  end

  private

  def make_request(verb, endpoint, body = nil, query_params: nil)
    uri = URI("#{@api_url}#{endpoint}")
    
    # Add query parameters if provided
    if query_params
      uri.query = URI.encode_www_form(query_params)
      print uri
    end
    
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
