# frozen_string_literal: true

require "monitor"
require_relative "event_trigger/version"
require_relative "event_trigger/threading"
require_relative "event_trigger/configuration"
require_relative "event_trigger/event"
require_relative "event_trigger/registry"
require_relative "event_trigger/provider"
require_relative "event_trigger/providers/twilio_client"
require_relative "event_trigger/providers/slack_provider"
require_relative "event_trigger/providers/email_provider"
require_relative "event_trigger/providers/webhook_provider"
require_relative "event_trigger/providers/discord_provider"
require_relative "event_trigger/providers/whatsapp_provider"
require_relative "event_trigger/providers/telegram_provider"
require_relative "event_trigger/providers/teams_provider"
require_relative "event_trigger/providers/sms_provider"
require_relative "event_trigger/dispatcher"
require_relative "event_trigger/defaults"
require_relative "event_trigger/railtie" if defined?(Rails::Railtie)

module EventTrigger
  class Error < StandardError; end

  class << self
    # Central configuration block:
    #
    #   EventTrigger.configure do |config|
    #     config.enabled = true
    #     config.slack.enabled = true
    #     config.slack.webhook_url = ENV["SLACK_WEBHOOK_URL"]
    #   end
    def configure
      yield configuration
    end

    # Access (and memoize) the global configuration object.
    # Never raises: returns a fresh Configuration if anything goes wrong.
    def configuration
      @configuration || EventTrigger.lock.synchronize { @configuration ||= Configuration.new }
    rescue StandardError
      @configuration ||= Configuration.new
    end

    # Reset configuration + handlers + provider registry to defaults.
    # Primarily useful for tests. Never raises.
    def reset!
      EventTrigger.lock.synchronize do
        @configuration = Configuration.new
        @handlers = Hash.new { |h, k| h[k] = [] }
        @last_result = nil
        Registry.reset!
      end
    rescue StandardError
      nil
    end

    # Register a handler block for a specific event name:
    #
    #   EventTrigger.on("loan.activated") do |event|
    #     # custom notification logic
    #   end
    #
    # Returns the registered block.
    def on(event_name, &block)
      raise ArgumentError, "EventTrigger.on requires a block" unless block_given?

      key = normalize_event_name(event_name)
      EventTrigger.lock.synchronize { handlers[key] << block }
      block
    end

    # Remove all handlers for an event (or all events when no name given).
    def off(event_name = nil)
      EventTrigger.lock.synchronize do
        if event_name.nil?
          @handlers = Hash.new { |h, k| h[k] = [] }
        else
          handlers.delete(normalize_event_name(event_name))
        end
      end
    end

    # Registered handlers hash: { "event.name" => [proc, ...] }
    def handlers
      @handlers ||= Hash.new { |h, k| h[k] = [] }
    end

    # Register a custom provider class under a symbolic name:
    #
    #   class SmsProvider < EventTrigger::Provider; end
    #   EventTrigger.register_provider(:sms, SmsProvider)
    def register_provider(name, klass)
      Registry.register(name, klass)
    end

    # The main public API:
    #
    #   EventTrigger.trigger("loan.activated", data: { loan_id: 123 })
    #
    # Builds an EventTrigger::Event and hands it to the Dispatcher,
    # which fans out to every enabled provider configured for that event.
    # Returns the Event object (unchanged). The provider-wise result hash
    # ({ event:, status:, providers: {...} }) is available as
    # EventTrigger.last_result and as event.last_result.
    #
    # NEVER RAISES: any unexpected internal error is logged and captured
    # in the result (status: "error") so the host app can never be harmed
    # by this gem.
    def trigger(event_name, data: {})
      event = build_event(event_name, data)
      begin
        result = Dispatcher.new(configuration).dispatch(event, handlers_for(event.name))
      rescue StandardError => e
        result = { event: event.name, status: "error", error: "#{e.class}: #{e.message}", providers: {} }
        safe_log("#{e.class}: #{e.message}")
      end
      @last_result = result
      event.last_result = result
      event
    end

    # Provider-wise result of the most recent trigger call, e.g.:
    #   { event: "loan.activated", status: "success",
    #     providers: { slack: "sent", email: "sent", discord: "skipped (disabled)", ... } }
    # Nil until the first trigger call.
    def last_result
      @last_result
    end

    # Handlers registered for a given event name (string).
    # Uses #fetch so unknown event names don't grow the handler table.
    def handlers_for(event_name)
      EventTrigger.lock.synchronize { handlers.fetch(normalize_event_name(event_name), []).dup }
    rescue StandardError
      []
    end

    # Normalize event names to strings ("loan.activated").
    def normalize_event_name(name)
      name.to_s
    rescue StandardError
      ""
    end

    private

    # Builds the Event defensively: even a pathological payload (odd keys,
    # objects whose #to_s raises, non-hash data) cannot raise here.
    def build_event(event_name, data)
      Event.new(name: normalize_event_name(event_name), payload: data || {})
    rescue StandardError
      Event.new(name: "", payload: {})
    end

    # Logging must never raise into the host app.
    def safe_log(message)
      logger = configuration.logger
      return unless logger.respond_to?(:info)

      logger.info("[EventTrigger] #{message}")
    rescue StandardError
      nil
    end
  end
end
