# frozen_string_literal: true

require "time"
require_relative "../provider"
require_relative "http_poster"

module EventTrigger
  module Providers
    # Sends event notifications to Discord via an incoming-webhook URL,
    # using a rich embed payload (ported from RailsErrorNotifier).
    #
    # Config:
    #   config.discord.enabled = true
    #   config.discord.webhook_url = ENV["DISCORD_WEBHOOK_URL"]
    #   config.discord.username = "RailsErrorNotifier"  # optional
    #   config.discord.events = ["loan.activated", "loan.overdue"]
    #
    # Crash-safe: failures raise EventTrigger::Error, which the
    # Dispatcher logs — the host app never crashes because of Discord.
    class DiscordProvider < Provider
      include HttpPoster

      MAX_FIELD_VALUE = 1024

      def self.provider_name
        :discord
      end

      def deliver(event)
        url = config.webhook_url || config.url
        raise Error, "Discord webhook_url is not configured" if url.nil? || url.to_s.strip.empty?

        post_json(url.to_s, build_payload(event), { "Content-Type" => "application/json" }, service: "Discord")
        log("delivered event '#{event.name}'")
        true
      end


      private

      def build_payload(event)
        payload = event.payload
        backtrace_text = truncate_for_discord((payload[:backtrace] || payload["backtrace"] || ["No backtrace"]).first(10).join("\n"))
        context_text = truncate_for_discord((payload[:context] || payload["context"] || payload).inspect)
        {
          username: config.username || "RailsErrorNotifier",
          embeds: [
            {
              title: "🚨 Error Occurred",
              description: embed_description(event, payload),
              color: 0xFF0000,
              fields: [
                { name: "Backtrace", value: "```\n#{backtrace_text}\n```", inline: false },
                { name: "Context", value: "```\n#{context_text}\n```", inline: false }
              ],
              timestamp: Time.now.utc.iso8601
            }
          ]
        }
      end

      def embed_description(event, payload)
        err = payload[:error] || payload["error"] || event.name
        truncate(err.to_s, 1500)
      end

      def truncate(str, limit = 1500)
        s = str.to_s
        s.length > limit ? "#{s[0, limit]}…" : s
      end

      def truncate_for_discord(text)
        truncate(text.to_s, MAX_FIELD_VALUE - 10) # leave room for ``` block
      end
    end
  end
end
