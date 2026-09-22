# frozen_string_literal: true

# NOTE: twilio-ruby is required lazily inside #deliver — see SmsProvider.
# Keeping it out of load time means the gem pays nothing when WhatsApp
# is disabled / unused (requirement: no eager provider deps).

require_relative "../provider"

module EventTrigger
  module Providers
    # Sends event notifications via WhatsApp using Twilio
    # (ported from RailsErrorNotifier).
    #
    # Config:
    #   config.whatsapp.enabled = true
    #   config.whatsapp.twilio_sid = ENV["TWILIO_ACCOUNT_SID"]
    #   config.whatsapp.twilio_token = ENV["TWILIO_AUTH_TOKEN"]
    #   config.whatsapp.twilio_from = "whatsapp:+14155238886"
    #   config.whatsapp.twilio_to = "whatsapp:+919876543210"
    #   config.whatsapp.events = ["payment.received", "loan.overdue"]
    #
    # Aliases: account_sid/sid, auth_token/token, from/to.
    # Per-trigger override: data: { whatsapp_to: "whatsapp:+..." }
    #
    # Crash-safe: missing gem/credentials/network errors raise
    # EventTrigger::Error, which the Dispatcher logs — the host app
    # never crashes because of WhatsApp.
    class WhatsappProvider < Provider
      MAX_BODY = 1000

      def self.provider_name
        :whatsapp
      end

      def deliver(event)
        client_class = twilio_client_class
        unless client_class
          raise Error, TwilioClient::GEM_MISSING_MESSAGE
        end

        sid = config.twilio_sid || config.account_sid || config.sid
        token = config.twilio_token || config.auth_token || config.token
        from = config.twilio_from || config.from
        to = event.payload[:whatsapp_to] || event.payload["whatsapp_to"] ||
             config.twilio_to || config.to

        raise Error, "WhatsApp twilio_sid is not configured" if blank?(sid)
        raise Error, "WhatsApp twilio_token is not configured" if blank?(token)
        raise Error, "WhatsApp sender (twilio_from) is not configured" if blank?(from)
        raise Error, "WhatsApp recipient (twilio_to) is not configured" if blank?(to)

        client = TwilioClient.resolve.new(sid.to_s, token.to_s)
        client.messages.create(
          from: normalize_number(from),
          to: normalize_number(to),
          body: build_body(event)
        )
        log("delivered event '#{event.name}' to #{to}")
        true
      end


      private

      # Thin wrapper around the lazy resolver — kept as an instance method
      # so tests can stub it (e.g. simulate "gem missing" deterministically).
      def twilio_client_class
        TwilioClient.resolve
      end

      def build_body(event)
        payload = event.payload
        err = payload[:error] || payload["error"]
        text =
          if err
            bt = payload[:backtrace] || payload["backtrace"]
            first = Array(bt).first || "No backtrace"
            ctx = payload[:context] || payload["context"]
            msg = "🚨 Error: #{err}\nBacktrace: #{first}"
            msg += "\nContext: #{ctx.inspect}" if ctx
            msg
          else
            summary = payload.map { |k, v| "#{k}: #{v}" }.join(", ")
            summary = payload.inspect if summary.empty?
            "[#{event.name}] #{summary}"
          end
        truncate(text)
      end

      # Twilio requires the whatsapp: scheme; add it when missing.
      def normalize_number(value)
        s = value.to_s.strip
        s.start_with?("whatsapp:") ? s : "whatsapp:#{s}"
      end

      def blank?(value)
        value.nil? || value.to_s.strip.empty?
      end

      def truncate(str, limit = MAX_BODY)
        s = str.to_s
        s.length > limit ? "#{s[0, limit]}…" : s
      end
    end
  end
end
