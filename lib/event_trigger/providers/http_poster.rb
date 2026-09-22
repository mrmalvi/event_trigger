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
    #
    # NOTE: faraday is loaded lazily (only on fallback) so apps that
    # never hit the network path pay no load cost.
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

      def request_json(method, url, body, headers = { "Content-Type" => "application/json" }, service: "HTTP")
        payload = JSON.generate(body)
        begin
          net_http_request(method, url, payload, headers, service)
        rescue EventTrigger::Error
          raise
        rescue StandardError => e
          # Only POST has a Faraday fallback today; other verbs re-raise.
          raise e unless method.to_s.downcase == "post"

          faraday_post(url, payload, headers, service, e)
        end
      end

      def net_http_post(url, payload, headers, service)
        net_http_request(:post, url, payload, headers, service)
      end

      def net_http_request(method, url, payload, headers, service)
        uri = URI.parse(url.to_s)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        # Hard timeouts at both ends: connect, read AND write. Without these
        # a stalled peer could block the host app's web worker indefinitely.
        http.open_timeout = 5
        http.read_timeout = 10
        http.write_timeout = 10 if http.respond_to?(:write_timeout=)
        http.continue_timeout = 5 if http.respond_to?(:continue_timeout=)
        klass = case method.to_s.downcase
                when "get" then Net::HTTP::Get
                when "put" then Net::HTTP::Put
                when "patch" then Net::HTTP::Patch
                when "delete" then Net::HTTP::Delete
                else Net::HTTP::Post
                end
        request = klass.new(uri.request_uri, headers)
        request.body = payload unless method.to_s.downcase == "get"
        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "#{service} delivery failed (HTTP #{response.code}): #{truncate(response.body)}"
        end
        response
      end

      def faraday_post(url, payload, headers, service, original_error)
        require "faraday"
        conn = Faraday.new do |f|
          f.options.timeout = 10
          f.options.open_timeout = 5
        end
        response = conn.post(url.to_s, payload, headers)
        unless response.success?
          raise Error, "#{service} delivery failed (HTTP #{response.status}): #{truncate(response.body)}"
        end
        response
      rescue LoadError
        raise original_error
      end

      # Keep error messages bounded — a huge HTML error page must not blow
      # up memory or logs.
      def truncate(str, limit = 500)
        s = str.to_s
        s.length > limit ? "#{s[0, limit]}…" : s
      rescue StandardError
        ""
      end
    end
  end
end
