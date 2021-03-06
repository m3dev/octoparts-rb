require 'helper'
require 'active_support/core_ext/string/inflections'

class TestClient < Test::Unit::TestCase
  def setup
    @client = Octoparts::Client.new
  end

  sub_test_case "#invoke" do
    test "normal invoke" do
      VCR.use_cassette 'invoke_example' do
        response = @client.invoke({
          "request_meta" => {
            "id" => "test",
            "timeout" => 500
          },
          "requests" => [
            "part_id" => "echo",
            "params" => [
              {
                "key" => "fooValue",
                "value" => "test"
              }
            ]
          ]
        })
        body = response.body
        assert { body.class == Octoparts::Model::AggregateResponse }
        assert { body.response_meta.class == Octoparts::Model::ResponseMeta }
        assert { body.responses.first.class == Octoparts::Model::PartResponse }
        assert { body.responses.first.cache_control.class == Octoparts::Model::CacheControl }
        assert { body.responses.size == 1 }
        assert { body.responses.first.contents =~ /"test"/ }
      end
    end

    test "normal invoke with AggregateRequest model" do
      VCR.use_cassette 'invoke_with_aggregate_request' do
        aggregate_request = Octoparts.build_aggregate_request do
          request_meta(id: 'test', timeout: 500)
          requests do
            part_request(part_id: 'echo').add_param('fooValue', 'test')
          end
        end
        stub_request(:post, 'localhost:9000')
        response = @client.invoke(aggregate_request)
        body = response.body
        assert { body.class == Octoparts::Model::AggregateResponse }
        assert { body.response_meta.class == Octoparts::Model::ResponseMeta }
        assert { body.responses.first.class == Octoparts::Model::PartResponse }
        assert { body.responses.first.cache_control.class == Octoparts::Model::CacheControl }
        assert { body.responses.size == 1 }
        assert { body.responses.first.contents =~ /"test"/ }
        assert_requested(:post, "http://localhost:9000/octoparts/2") do |req|
          req.body == '{"requestMeta":{"id":"test","timeout":500},"requests":[{"partId":"echo","params":[{"key":"fooValue","value":"test"}]}]}'
        end
      end
    end

    test "normal invoke when 2 requests" do
      VCR.use_cassette 'invoke_with_2_requests' do
        response = @client.invoke({
          request_meta: {
            id: "test",
            timeout: 500
          },
          requests: [
            {
              part_id: "echo",
              params: [
                {
                  key: "fooValue",
                  value: "test"
                }
              ]
            },
            {
              part_id: "echo",
              params: [
                {
                  key: "fooValue",
                  value: "hoge"
                }
              ]
            }
          ]
        })
        body = response.body
        assert { body.class == Octoparts::Model::AggregateResponse }
        assert { body.response_meta.class == Octoparts::Model::ResponseMeta }
        assert { body.responses.first.class == Octoparts::Model::PartResponse }
        assert { body.responses.first.cache_control.class == Octoparts::Model::CacheControl }
        assert { body.responses.size == 2 }
        assert { body.responses.first.contents =~ /"test"/ }
        assert { body.responses.last.contents =~ /"hoge"/ }
      end
    end

    test "invalid parameters" do
      VCR.use_cassette 'invoke_with_invalid_parameters' do
        assert_raise Octoparts::ClientError do
          response = @client.invoke({
            "request_meta" => {
              "timeout" => 500
            }
          })
        end
      end
    end

    test "invalid argument" do
      assert_raise Octoparts::ArgumentError do
        @client.invoke(nil)
      end
    end
  end

  sub_test_case "#invalidate_cache" do
    test "post /invalidate/part/PART_ID" do
      VCR.use_cassette 'invalidate_cache_with_part_id' do
        stub_request(:post, 'localhost:9000')
        @client.invalidate_cache('echo')
        assert_requested(:post, 'http://localhost:9000/octoparts/2/cache/invalidate/part/echo')
      end
    end

    test "post /invalidate/part/PART_ID/PARAM_NAME/PARAM_VALUE" do
      VCR.use_cassette 'invalidate_cache_with_part_id_and_key_value' do
        stub_request(:post, 'localhost:9000')
        @client.invalidate_cache('echo', param_name: 'fooValue', param_value: 'test')
        assert_requested(:post, 'http://localhost:9000/octoparts/2/cache/invalidate/part/echo/fooValue/test')
      end
    end
  end

  sub_test_case "#invalidate_cache_group" do
    test "post /invalidate/cache-group/GROUP_NAME/parts" do
      VCR.use_cassette 'invalidate_cache_group_with_group_name' do
        stub_request(:post, 'localhost:9000')
        @client.invalidate_cache_group('echo_group')
        assert_requested(:post, 'http://localhost:9000/octoparts/2/cache/invalidate/cache-group/echo_group/parts')
      end
    end

    test "post /invalidate/cache-group/GROUP_NAME/params/PARAM_VALUE" do
      VCR.use_cassette 'invalidate_cache_group_with_param_value' do
        stub_request(:post, 'localhost:9000')
        @client.invalidate_cache_group('echo_group', param_value: 'fooValue')
        assert_requested(:post, 'http://localhost:9000/octoparts/2/cache/invalidate/cache-group/echo_group/params/fooValue')
      end
    end
  end

  sub_test_case "timeout" do
    setup do
      @exception_class = defined?(Faraday::TimeoutError) ? Faraday::TimeoutError : Faraday::Error::TimeoutError
    end

    teardown do
      Octoparts.configure do |c|
        c.timeout_sec = nil
      end
    end

    test "timeout_sec option" do
      stub_request(:get, 'localhost:9000').to_raise(Timeout::Error)
      assert_raise @exception_class do
        Octoparts::Client.new(timeout_sec: 0).get('/')
      end
    end

    test "open_timeout_sec option" do
      stub_request(:get, 'localhost:9000').to_raise(Timeout::Error)
      Octoparts.configure do |c|
        c.timeout_sec = 0
      end
      assert_raise @exception_class do
        Octoparts::Client.new.get('/')
      end
    end
  end

  sub_test_case "error case" do
    test "500 error" do
      stub_request(:any, 'localhost:9000/500').to_return(status: 500, body: 'NG', headers: { 'Content-Length' => 2})
      assert_raise Octoparts::ServerError do
        Octoparts::Client.new(timeout_sec: 0).get('/500')
      end
    end
  end

  sub_test_case "#create_request_body" do
    test "return camelized keys" do
      request_hash = {
        request_meta: {
          id: 1,
          service_id: 'hoge',
          user_id: 2,
          session_id: 3,
          request_url: 'http://test.com',
          user_agent: 'ruby',
          timeout: 4
        },
        requests: [{
          part_id: 'fuga',
          id: 5,
          params: [{
            key: 'value_of_key',
            value: 'value_of_value'
          }]
        }]
      }
      body_json = Octoparts::Client.new(timeout_sec: 0).send(:create_request_body, request_hash)
      body = JSON.parse(body_json, symbolize_names: true)
      assert { body[:requestMeta] != nil }
      request_meta = body[:requestMeta]
      assert { request_meta[:id] == 1 }
      assert { request_meta[:serviceId] == 'hoge' }
      assert { request_meta[:userId] == 2 }
      assert { request_meta[:sessionId] == 3 }
      assert { request_meta[:requestUrl] == 'http://test.com' }
      assert { request_meta[:userAgent] == 'ruby' }
      assert { request_meta[:timeout] == 4 }
      assert { body[:requests].instance_of?(Array) }
      request_item = body[:requests].first
      assert { request_item[:partId] == 'fuga' }
      assert { request_item[:id] == 5 }
      assert { request_item[:params] != nil }
      assert { request_item[:params].first[:key] == 'value_of_key' }
      assert { request_item[:params].first[:value] == 'value_of_value' }
    end
  end
end
