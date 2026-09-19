# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "time"
require_relative "../provider"

module EventTrigger
  module Providers
    # Sends event notifications to Slack (or any Slack-compatible /
    # Discord-compatible incoming-webhook URL).
    #
    # Config:
    #   config.slack.enabled = true
    #   config.slack.webhook_url = ENV["SLACK_WEBHOOK_URL"]
    #   config.slack.events = ["loan.activated"]
    #
    # Payload behaviour:
    # - Slack incoming webhooks (hooks.slack.com) receive { text: ... }.
    # - All other URLs (e.g. Discord-style webhooks) receive a rich embed
    #   payload with error/backtrace/context fields, truncated to stay
    #   within message limits.
    class SlackProvider < Provider
      MAX_TEXT = 1500

      def self.provider_name
        :slack
      end

      def deliver(event)
        url = config.webhook_url || config.url
        raise Error, "Slack webhook_url is not configured" if url.nil? || url.to_s.strip.empty?

        body = build_payload(url.to_s, event)
        post_json(url.to_s, body)
        log("delivered event '#{event.name}'")
        true
      end

      private

      def build_payload(url, event)
        payload = event.payload
        if url.include?("hooks.slack.com")
          { text: slack_text(event, payload) }
        else
          {
            username: "RailsErrorNotifier",
            embeds: [
              {
                title: "🚨 Error Occurred",
                description: embed_description(event, payload),
                color: 0xFF0000,
                fields: [
                  { name: "Event", value: "```\n#{truncate(event.name)}\n```", inline: false },
                  { name: "Backtrace", value: "```\n#{backtrace_text(payload)}\n```", inline: false },
                  { name: "Context", value: "```\n#{context_text(payload)}\n```", inline: false }
                ],
                timestamp: Time.now.utc.iso8601
              }
            ]
          }
        end
      end

      # Slack text format: human summary; falls back to error/backtrace keys
      # when present, otherwise dumps the generic payload.
      def slack_text(event, payload)
        if payload[:error] || payload["error"]
          err = payload[:error] || payload["error"]
          bt = payload[:backtrace] || payload["backtrace"]
          lines = [err.to_s]
          lines += Array(bt) if bt
          lines.join("\n")
        else
          summary = payload.map { |k, v| "#{k}: #{v}" }.join(", ")
          summary = event.payload.inspect if summary.empty?
          "[#{event.name}] #{summary}"
        end
      end

      def embed_description(event, payload)
        err = payload[:error] || payload["error"] || event.name
        truncate(err.to_s)
      end

      def backtrace_text(payload)
        bt = payload[:backtrace] || payload["backtrace"] || ["No backtrace"]
        truncate_for_discord(Array(bt).first(10).join("\n"))
      end

      def context_text(payload)
        ctx = payload[:context] || payload["context"] || payload
        truncate_for_discord(ctx.inspect)
      end

      def truncate(str, limit = MAX_TEXT)
        s = str.to_s
        s.length > limit ? "#{s[0, limit]}…" : s
      end

      def truncate_for_discord(str, limit = 1000)
        truncate(str, limit)
      end

      def post_json(url, body)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 10
        request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
        request.body = JSON.generate(body)
        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "Slack delivery failed (HTTP #{response.code}): #{response.body}"
        end
        response
      end
    end
  end
end
