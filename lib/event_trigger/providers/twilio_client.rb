# frozen_string_literal: true

module EventTrigger
  module Providers
    # Lazy, crash-safe resolver for the Twilio client class.
    #
    # - Returns the already-loaded (or test-stubbed) client when present,
    #   so `twilio-ruby` is never loaded until a Twilio-backed provider
    #   (SMS / WhatsApp) is actually used.
    # - Requires the gem on demand on first use.
    # - Raises EventTrigger::Error (never LoadError/NameError) when the
    #   gem is missing or broken, so the Dispatcher can log it and the
    #   host app keeps running.
    module TwilioClient
      GEM_MISSING_MESSAGE =
        'twilio-ruby gem is not installed (add `gem "twilio-ruby"` to your Gemfile)'.freeze

      def self.resolve
        klass = loaded_client
        return klass if klass

        begin
          require "twilio-ruby"
        rescue LoadError, StandardError => e
          raise Error, "#{GEM_MISSING_MESSAGE} (#{e.class}: #{e.message})"
        end
        loaded_client || raise(Error, GEM_MISSING_MESSAGE)
      end

      # Explicit Object-space lookup (instead of lexical `defined?`) so
      # test doubles (stub_const / hide_const) behave predictably.
      def self.loaded_client
        return nil unless ::Object.const_defined?(:Twilio)

        rest = ::Twilio.const_defined?(:REST, false) ? ::Twilio::REST : nil
        return nil unless rest
        return nil unless rest.const_defined?(:Client, false)

        rest.const_get(:Client, false)
      rescue StandardError
        nil
      end
    end
  end
end
