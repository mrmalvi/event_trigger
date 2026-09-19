# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "../provider"

module EventTrigger
  module Providers
    # POSTs the event as JSON to a configured HTTP endpoint.
    #
    # Config:
    #   config.webhook.enabled = true
    #   config.webhook.url = "https://example.com/hooks/events"
    #   config.webhook.headers = { "Authorization" => "Bearer ..." }
    #   config.webhook.events = ["loan.activated"]
    class WebhookProvider < Provider
      def self.provider_name
        :webhook
      end

      def deliver(event)
        url = config.url
        raise Error, "Webhook url is not configured" if url.nil? || url.to_s.strip.empty?

        post_json(url.to_s, event_to_json(event), headers)
        log("delivered event '#{event.name}' to #{url}")
        true
      end

      private

      def headers
        { "Content-Type" => "application/json" }.merge(config.headers || {})
      end

      def event_to_json(event)
        {
          event: event.name,
          payload: stringify(event.payload),
          timestamp: event.timestamp.to_s
        }
      end

      def stringify(hash)
        hash.each_with_object({}) { |(k, v), m| m[k.to_s] = v }
      end

      def post_json(url, body, headers)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 10
        request = Net::HTTP::Post.new(uri.request_uri, headers)
        request.body = JSON.generate(body)
        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "Webhook delivery failed (HTTP #{response.code}): #{response.body}"
        end
        response
      end
    end
  end
end
