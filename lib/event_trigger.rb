# frozen_string_literal: true

require_relative "event_trigger/version"
require_relative "event_trigger/configuration"
require_relative "event_trigger/event"
require_relative "event_trigger/registry"
require_relative "event_trigger/provider"
require_relative "event_trigger/providers/slack_provider"
require_relative "event_trigger/providers/email_provider"
require_relative "event_trigger/providers/webhook_provider"
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
    def configuration
      @configuration ||= Configuration.new
    end

    # Reset configuration + handlers + provider registry to defaults.
    # Primarily useful for tests.
    def reset!
      @configuration = Configuration.new
      @handlers = Hash.new { |h, k| h[k] = [] }
      Registry.reset!
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
      handlers[key] << block
      block
    end

    # Remove all handlers for an event (or all events when no name given).
    def off(event_name = nil)
      if event_name.nil?
        @handlers = Hash.new { |h, k| h[k] = [] }
      else
        handlers.delete(normalize_event_name(event_name))
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
    # Returns the Event object.
    def trigger(event_name, data: {})
      event = Event.new(name: normalize_event_name(event_name), payload: data || {})
      Dispatcher.new(configuration).dispatch(event, handlers_for(event.name))
      event
    end

    # Handlers registered for a given event name (string).
    def handlers_for(event_name)
      handlers[normalize_event_name(event_name)].dup
    end

    # Normalize event names to strings ("loan.activated").
    def normalize_event_name(name)
      name.to_s
    end
  end
end
