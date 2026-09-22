# frozen_string_literal: true

require_relative "../provider"
require_relative "http_poster"

module EventTrigger
  module Providers
    # Sends event notifications to Telegram via the Bot API.
    #
    #   API: POST https://api.telegram.org/bot<BOT_TOKEN>/sendMessage
    #
    # Config:
    #   config.telegram.enabled = true
    #   config.telegram.bot_token = ENV["TELEGRAM_BOT_TOKEN"]
    #   config.telegram.chat_id = ENV["TELEGRAM_CHAT_ID"]
    #   config.telegram.events = ["loan.overdue"]
    #
    # Per-trigger override: data: { telegram_chat_id: "..." }
    # Crash-safe: failures raise EventTrigger::Error (Dispatcher logs them).
    class TelegramProvider < Provider
      include HttpPoster

      MAX_TEXT = 4000

      def self.provider_name
        :telegram
      end

      def deliver(event)
        token = config.bot_token
        chat_id = event.payload[:telegram_chat_id] || event.payload["telegram_chat_id"] || config.chat_id
        raise Error, "Telegram bot_token is not configured" if blank?(token)
        raise Error, "Telegram chat_id is not configured" if blank?(chat_id)

        url = "https://api.telegram.org/bot#{token}/sendMessage"
        response = post_json(url, { chat_id: chat_id.to_s, text: message_text(event) }, service: "Telegram")
        parsed = parse_json(response_body(response))
        # Telegram returns { "ok": true, ... } on success.
        if parsed.is_a?(Hash) && parsed.key?("ok") && parsed["ok"] != true
          raise Error, "Telegram delivery failed: #{response_body(response)}"
        end
        log("delivered event '#{event.name}'")
        true
      end


      private

      def message_text(event)
        payload = event.payload
        err = payload[:error] || payload["error"]
        text =
          if err
            bt = payload[:backtrace] || payload["backtrace"]
            lines = ["🚨 #{err}"]
            lines << Array(bt).first.to_s if bt
            lines.join("\n")
          else
            summary = payload.map { |k, v| "#{k}: #{v}" }.join(", ")
            summary = payload.inspect if summary.empty?
            "[#{event.name}] #{summary}"
          end
        truncate(text)
      end

      def response_body(response)
        response.respond_to?(:body) ? response.body : response.to_s
      end

      def parse_json(str)
        require "json"
        JSON.parse(str.to_s)
      rescue StandardError
        nil
      end

      def blank?(value)
        value.nil? || value.to_s.strip.empty?
      end

      def truncate(str, limit = MAX_TEXT)
        s = str.to_s
        s.length > limit ? "#{s[0, limit]}…" : s
      end
    end
  end
end
