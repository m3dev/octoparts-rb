require 'active_support/core_ext/hash/keys'
require 'active_support/core_ext/object/blank'
require 'uri'
require 'net/http'
require 'json'

module Octoparts
  class Client
    OCTOPARTS_API_ENDPOINT_PATH = '/octoparts/2'
    CACHE_API_ENDPOINT_PATH = "#{OCTOPARTS_API_ENDPOINT_PATH}/cache"

    def initialize(endpoint: nil, headers: {}, timeout_sec: nil, open_timeout_sec: nil)
      @endpoint = endpoint || Octoparts.configuration.endpoint
      @timeout_sec = timeout_sec || Octoparts.configuration.timeout_sec
      @open_timeout_sec = open_timeout_sec || Octoparts.configuration.open_timeout_sec
      @headers = Octoparts.configuration.headers.merge(headers)
    end

    def get(path, params = {}, headers = {})
      process(:get, path, params, nil, headers)
    end

    def post(path, body = nil, headers = {})
      process(:post, path, {}, body, headers)
    end

    # Post an AggregateRequest and return AggregateResponse.
    # @param [Octoparts::Model::AggregateRequest, Hash] params aggregate request
    # @return [Octoparts::Response] response object
    def invoke(params)
      body = create_request_body(params)
      headers = { content_type: 'application/json' }
      resp = post(OCTOPARTS_API_ENDPOINT_PATH, body, headers)
      Response.new(
        Model::AggregateResponse.new.extend(Representer::AggregateResponseRepresenter).from_json(resp.body),
        resp.to_hash,
        resp.code
      )
    end

    # TODO: doc
    def invalidate_cache(part_id, param_name: nil, param_value: nil)
      cache_path = if param_name
        "/invalidate/part/#{part_id}/#{param_name}/#{param_value}"
      else
        "/invalidate/part/#{part_id}"
      end
      post_cache_api(cache_path)
    end

    # TODO: doc
    def invalidate_cache_group(cache_group_name, param_value: nil)
      cache_path = if param_value
        "/invalidate/cache-group/#{cache_group_name}/params/#{param_value}"
      else
        "/invalidate/cache-group/#{cache_group_name}/parts"
      end
      post_cache_api(cache_path)
    end

    private

    def post_cache_api(path)
      encoded_path_segments = path.split('/').map { |seg| URI.encode_www_form_component(seg) }.join('/')
      escaped_path = "#{CACHE_API_ENDPOINT_PATH}#{encoded_path_segments}"
      resp = post(escaped_path)
      Response.new(
        resp.body,
        resp.to_hash,
        resp.code
      )
    end

    def process(method, path, params, body, headers)
      uri = URI(@endpoint)
      uri.path = path
      uri.query = URI.encode_www_form(params) unless params.blank?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = @timeout_sec
      http.open_timeout = @open_timeout_sec

      request = case method
                when :get
                  Net::HTTP::Get.new(uri)
                when :post
                  Net::HTTP::Post.new(uri)
                else
                  raise ArgumentError, "Unsupported HTTP method: #{method}"
                end

      request.body = body if body
      headers.each { |key, value| request[key] = value }
      @headers.each { |key, value| request[key] = value }

      response = http.request(request)

      if error = Octoparts::ResponseError.from_response(response)
        raise error
      end
      response
    end

    def create_request_body(model)
      aggregate_request = case model
                          when Hash
                            stringify_params = model.deep_stringify_keys
                            Model::AggregateRequest.new.extend(Representer::AggregateRequestRepresenter).from_hash(stringify_params)
                          when Octoparts::Model::AggregateRequest
                            model.extend(Representer::AggregateRequestRepresenter)
                          else
                            raise Octoparts::ArgumentError
                          end
      aggregate_request.to_json(user_options: {camelize: true})
    end
  end
end
