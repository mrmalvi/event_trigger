# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module EventTrigger
  module Providers
    # Shared JSON POST helper with a Net::HTTP -> Faraday fallback chain.
    #
    # Primary transport is stdlib Net::HTTP (zero extra deps). If the
    # request itself raises (DNS, timeout, connection error), it falls
    # back to Faraday when available. HTTP error statuses raise
    # EventTrigger::Error directly (no retry — same result expected).
    module HttpPoster
      private

      def post_json(url, body, headers = { "Content-Type" => "application/json" }, service: "HTTP")
        payload = JSON.generate(body)
        begin
          net_http_post(url, payload, headers, service)
        rescue EventTrigger::Error
          raise
        rescue StandardError => e
          faraday_post(url, payload, headers, service, e)
        end
      end

      def net_http_post(url, payload, headers, service)
        uri = URI.parse(url.to_s)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 10
        request = Net::HTTP::Post.new(uri.request_uri, headers)
        request.body = payload
        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "#{service} delivery failed (HTTP #{response.code}): #{response.body}"
        end
        response
      end

      def faraday_post(url, payload, headers, service, original_error)
        require "faraday"
        response = Faraday.post(url.to_s, payload, headers)
        unless response.success?
          raise Error, "#{service} delivery failed (HTTP #{response.status}): #{response.body}"
        end
        response
      rescue LoadError
        raise original_error
      end
    end
  end
end
