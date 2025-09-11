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

  def create_attachment(file)
    create_attachments([file])
  end

  def all_attachments
    response = make_request(:get, "/docs/#{@document_id}/attachments")
    response['records']
  end

  def delete_unused_attachments
    make_request(:post, "/docs/#{@document_id}/attachments/removeUnused")
  end

  def create_attachments(files)
    form_data = files.map do |file|
      ["upload", file, { filename: File.basename(file.path) }]
    end
    
    make_multipart_request(:post, "/docs/#{@document_id}/attachments", form_data)
  end

  def delete_record(table_id, record_id)
    delete_records(table_id, [record_id])
  end

  def delete_records(table_id, record_ids)
    make_request(:post, "/docs/#{@document_id}/tables/#{table_id}/data/delete", record_ids)
  end

  def delete_all_records(table_id)
    records = records(table_id)
    ids = records.map { |record| record["id"] }
    delete_records(table_id, ids)
  end

  private

  def fields_for_data(data)
    { fields: data }
  end

  def make_request(verb, endpoint, body = nil, query_params: nil)
    uri = URI("#{@api_url}#{endpoint}")
    
    if query_params
      uri.query = URI.encode_www_form(query_params)
    end
    
    http = create_http_connection(uri)
    request = build_request(verb, uri)
    request['Content-Type'] = 'application/json'
    
    if body && [:post, :put, :patch].include?(verb)
      request.body = body.to_json
    end
    
    response = http.request(request)
    handle_response(response, "#{verb.upcase} #{endpoint}")
  end

  def make_multipart_request(verb, endpoint, form_data)
    uri = URI("#{@api_url}#{endpoint}")
    http = create_http_connection(uri)
    request = build_request(verb, uri)
    request.set_form(form_data, "multipart/form-data")
    
    response = http.request(request)
    handle_response(response, "#{verb.upcase} #{endpoint}")
  end

  def create_http_connection(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http
  end

  def build_request(verb, uri)
    request_class = Net::HTTP.const_get(verb.to_s.capitalize)
    request = request_class.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    request
  end

  def handle_response(response, operation)
    if response.code == '200' || response.code == '201'
      JSON.parse(response.body)
    else
      raise "Failed to #{operation}: #{response.code} - #{response.body}"
    end
  end
end
