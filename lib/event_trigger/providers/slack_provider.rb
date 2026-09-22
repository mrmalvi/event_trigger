# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "time"
require_relative "../provider"
require_relative "http_poster"

module EventTrigger
  module Providers
    # Sends event notifications to Slack.
    #
    # Two modes (existing webhook mode is untouched):
    #
    # 1. Legacy incoming-webhook mode (unchanged):
    #      config.slack.webhook_url = ENV["SLACK_WEBHOOK_URL"]
    #    - hooks.slack.com URLs receive { text: ... }.
    #    - any other URL receives the Discord-style embed payload.
    #
    # 2. NEW Slack Web API mode (chat.postMessage), used only when BOTH
    #    token + channel are set:
    #      config.slack.token = ENV["SLACK_BOT_TOKEN"]
    #      config.slack.channel = ENV["SLACK_CHANNEL"]  # e.g. "#alerts" or "C123"
    #      API: POST https://slack.com/api/chat.postMessage
    #      Auth: Authorization: Bearer <token>
    #
    # Common:
    #   config.slack.enabled = true
    #   config.slack.events = ["loan.activated", "payment.received"]
    class SlackProvider < Provider
      MAX_TEXT = 1500

      WEB_API_URL = "https://slack.com/api/chat.postMessage"

      def self.provider_name
        :slack
      end

      include HttpPoster

      def deliver(event)
        # --- NEW: Web API mode (additive; webhook path below untouched) ---
        token = config.token
        channel = config.channel
        if present?(token) && present?(channel)
          return deliver_via_web_api(event, token.to_s, channel.to_s)
        end

        # --- Existing webhook mode (byte-for-byte behaviour preserved) ---
        url = config.webhook_url || config.url
        raise Error, "Slack webhook_url is not configured" if url.nil? || url.to_s.strip.empty?

        body = build_payload(url.to_s, event)
        post_json(url.to_s, body, { "Content-Type" => "application/json" }, service: "Slack")
        log("delivered event '#{event.name}'")
        true
      end


      private

      def deliver_via_web_api(event, token, channel)
        body = { channel: channel, text: slack_text(event, event.payload) }
        response = post_json(
          WEB_API_URL, body,
          { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" },
          service: "Slack"
        )
        parsed = parse_json(response.body)
        unless parsed.is_a?(Hash) && parsed["ok"] == true
          raise Error, "Slack Web API error: #{response.body}"
        end
        log("delivered event '#{event.name}' via chat.postMessage")
        true
      end

      def parse_json(str)
        JSON.parse(str.to_s)
      rescue StandardError
        nil
      end

      def present?(value)
        !value.nil? && !value.to_s.strip.empty?
      end

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
    end
  end
end
