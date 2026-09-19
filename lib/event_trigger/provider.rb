# frozen_string_literal: true

module EventTrigger
  # Common interface every notification provider must implement.
  #
  # To add a new provider, subclass this and implement #deliver(event):
  #
  #   class SmsProvider < EventTrigger::Provider
  #     def deliver(event)
  #       # send SMS using config ...
  #     end
  #   end
  #   EventTrigger.register_provider(:sms, SmsProvider)
  #
  # Helpers available to subclasses:
  #   - #config        -> ProviderConfig for this provider
  #   - #global_config -> full EventTrigger::Configuration
  #   - #log(message)  -> write to configured logger, if any
  class Provider
    attr_reader :config, :global_config

    def initialize(config:, global_config:)
      @config = config
      @global_config = global_config
    end

    # Deliver the notification for +event+. Must be implemented by subclasses.
    def deliver(_event)
      raise NotImplementedError, "#{self.class} must implement #deliver(event)"
    end

    # Symbolic name derived from class name, e.g. SlackProvider -> :slack.
    # Custom providers can override .provider_name.
    def self.provider_name
      name.to_s.split("::").last.to_s.sub(/Provider\z/, "").downcase.to_sym
    end

    def provider_name
      self.class.provider_name
    end

    protected

    def log(message)
      logger = global_config.logger
      logger&.info("[EventTrigger][#{provider_name}] #{message}")
    end
  end
end
