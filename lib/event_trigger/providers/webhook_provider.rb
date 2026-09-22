# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "../provider"
require_relative "http_poster"

module EventTrigger
  module Providers
    # Generic HTTP webhook provider for any custom system.
    #
    # Existing behaviour (unchanged): POSTs { event:, payload:,
    # timestamp: } as JSON to config.webhook.url with optional
    # config.webhook.headers.
    #
    # NEW additive options (only used when set):
    #   config.webhook.method = :post        # :post (default), :put, :patch, :delete, :get
    # NOTE: ProviderConfig defines Object#method, so write the verb via
    # `config.webhook[:method] = :post` (reader also via config[:method]).
    #   config.webhook.url = ENV["EVENT_WEBHOOK_URL"]
    #   config.webhook.headers = { "Authorization" => "Bearer ..." }
    #
    # method is normalized (:POST/"post" all work); unknown verbs fall back
    # to POST so old configs never break.
    class WebhookProvider < Provider
      include HttpPoster

      def self.provider_name
        :webhook
      end

      def deliver(event)
        url = config.url
        raise Error, "Webhook url is not configured" if url.nil? || url.to_s.strip.empty?

        request_json(http_method, url.to_s, event_to_json(event), headers, service: "Webhook")
        log("delivered event '#{event.name}' to #{url}")
        true
      end


      private

      def http_method
        m = ((config[:method] rescue nil) || :post).to_s.downcase
        %w[get post put patch delete].include?(m) ? m.to_sym : :post
      end

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
    end
  end
end
