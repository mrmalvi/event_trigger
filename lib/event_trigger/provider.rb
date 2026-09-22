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
  # Normalized alias: #send(event_name, data) builds an Event and
  # delegates to #deliver. Built-in providers implement it; custom
  # providers get a default that does the same.
  #
  # Helpers available to subclasses:
  #   - #config        -> ProviderConfig for this provider
  #   - #global_config -> full EventTrigger::Configuration
  #   - #log(message)  -> write to configured logger, if any (never logs credentials)
  class Provider
    # Keys that must never appear in logs (case-insensitive substring match).
    SECRET_KEYS = %w[token secret password passwd api_key apikey auth authorization bearer webhook].freeze

    attr_reader :config, :global_config

    def initialize(config:, global_config:)
      @config = config
      @global_config = global_config
    end

    # Deliver the notification for +event+. Must be implemented by subclasses.
    def deliver(_event)
      raise NotImplementedError, "#{self.class} must implement #deliver(event)"
    end

    # Normalized interface: provider.send(event_name, data)
    #
    # NOTE: this intentionally shadows Ruby's Object#send for the
    # notification signature. Calls that are clearly internal Ruby sends
    # are forwarded to Object#send so frameworks/reflection keep working:
    #   provider.send(:deliver, event)      -> Object#send
    #   provider.send(:some_helper, 1, 2)   -> Object#send
    #   provider.send("loan.activated", {}) -> notification (deliver)
    #   provider.send("loan.activated")     -> notification (empty payload)
    # Ambiguous single-symbol form (provider.send(:foo)) is treated as
    # Object#send; pass a String event name (or a data Hash) to notify.
    def send(event_name, *args, &block)
      notification =
        if args.size == 1
          args.first.nil? || args.first.is_a?(Hash)
        elsif args.empty?
          !event_name.is_a?(Symbol)
        else
          false
        end

      return __send__(event_name, *args, &block) unless notification

      deliver(Event.new(name: event_name.to_s, payload: args.first || {}))
    end

    # Normalized result wrapper: { provider:, status:, error: }.
    # Never raises — failures are captured, never stop other providers.
    def safe_send(event_name, data = {})
      send(event_name, data)
      { provider: provider_name, status: "sent", error: nil }
    rescue StandardError => e
      { provider: provider_name, status: "failed", error: "#{e.class}: #{e.message}" }
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
      return unless logger.respond_to?(:info)

      logger.info("[EventTrigger][#{provider_name}] #{redact(message)}")
    rescue StandardError
      nil
    end

    # Strip credential-looking fragments before they reach the log.
    def redact(message)
      str = message.to_s
      SECRET_KEYS.each do |key|
        str = str.gsub(/#{key}[^,\s\]}]*[\w\-\.\/~\+=\/]+/i, "#{key}=[FILTERED]")
      end
      str
    rescue StandardError
      "[unprintable]"
    end
  end
end
