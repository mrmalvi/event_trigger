# frozen_string_literal: true

require_relative "../provider"

module EventTrigger
  module Providers
    # Sends SMS notifications. Pluggable interface — today backed by
    # Twilio (lazy-loaded, only when this provider is enabled/used).
    #
    #   Twilio Messaging API base: https://api.twilio.com/2010-04-01
    #
    # Config:
    #   config.sms.enabled = true
    #   config.sms.provider = :twilio            # only :twilio supported today
    #   config.sms.account_sid = ENV["TWILIO_ACCOUNT_SID"]
    #   config.sms.auth_token = ENV["TWILIO_AUTH_TOKEN"]
    #   config.sms.from = ENV["TWILIO_FROM"]     # E.164 number, e.g. +15551234567
    #   config.sms.events = ["payment.received"]
    #
    # Per-trigger overrides: data: { sms_to:, sms_body: }
    # Crash-safe: failures raise EventTrigger::Error (Dispatcher logs them).
    class SmsProvider < Provider
      MAX_BODY = 1000

      def self.provider_name
        :sms
      end

      def deliver(event)
        name = (config.provider || :twilio).to_sym
        raise Error, "SMS provider #{name.inspect} is not supported (only :twilio)" unless name == :twilio

        client_class = twilio_client_class
        unless client_class
          raise Error, TwilioClient::GEM_MISSING_MESSAGE
        end

        sid = config.account_sid || config.twilio_sid
        token = config.auth_token || config.twilio_token
        from = config.from || config.twilio_from
        to = event.payload[:sms_to] || event.payload["sms_to"] || config.to
        raise Error, "SMS account_sid is not configured" if blank?(sid)
        raise Error, "SMS auth_token is not configured" if blank?(token)
        raise Error, "SMS sender (from) is not configured" if blank?(from)
        raise Error, "SMS recipient (to) is not configured" if blank?(to)

        body = event.payload[:sms_body] || event.payload["sms_body"] || build_body(event)
        Twilio::REST::Client.new(sid.to_s, token.to_s).messages.create(
          from: from.to_s, to: to.to_s, body: truncate(body.to_s)
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
        err = event.payload[:error] || event.payload["error"]
        return err.to_s if err

        summary = event.payload.map { |k, v| "#{k}: #{v}" }.join(", ")
        summary = event.payload.inspect if summary.empty?
        "[#{event.name}] #{summary}"
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
