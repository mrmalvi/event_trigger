# frozen_string_literal: true

require "logger"

module EventTrigger
  # Per-provider configuration. Every provider (built-in or custom) gets
  # an instance of this class with its own +enabled+, +events+ and
  # provider-specific settings stored in +options+.
  class ProviderConfig
    attr_accessor :enabled
    attr_writer :events

    def initialize(enabled: false, events: nil)
      @enabled = enabled
      @events = events # nil => subscribed to ALL events
      @options = {}
    end

    # List of event names this provider cares about, or nil for "all events".
    # Always returns strings (or nil).
    def events
      return nil if @events.nil?

      Array(@events).map(&:to_s)
    end

    # True when this provider should run for +event_name+.
    # nil/empty events list means "all events".
    def subscribed_to?(event_name)
      list = events
      return true if list.nil? || list.empty?

      list.include?(event_name.to_s)
    end

    # Generic option bag for provider-specific settings
    # (webhook_url, from, url, ...). Allows:
    #   config.slack.webhook_url = "..."
    def method_missing(name, *args)
      name_str = name.to_s
      if name_str.end_with?("=")
        @options[name_str.chomp("=").to_sym] = args.first
      elsif @options.key?(name)
        @options[name]
      elsif args.empty?
        nil
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      true
    end

    def options
      @options.dup
    end

    def to_h
      { enabled: enabled, events: events }.merge(@options)
    end
  end

  # Global configuration object yielded by EventTrigger.configure.
  class Configuration
    attr_accessor :enabled, :logger
    attr_reader :slack, :email, :webhook, :discord, :whatsapp

    # Backwards-compatible top-level shortcuts required by the spec:
    #   config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]
    #   config.email_from = ENV["EVENT_TRIGGER_EMAIL_FROM"]
    # They delegate to the per-provider configs.
    def initialize
      @enabled = true
      @logger = nil
      @slack = ProviderConfig.new
      @email = ProviderConfig.new
      @webhook = ProviderConfig.new
      @discord = ProviderConfig.new
      @whatsapp = ProviderConfig.new
      @custom = {}
    end

    def slack_webhook_url
      slack.webhook_url
    end

    def slack_webhook_url=(value)
      slack.webhook_url = value
    end

    def email_from
      email.from
    end

    def email_from=(value)
      email.from = value
    end

    def discord_webhook_url
      discord.webhook_url
    end

    def discord_webhook_url=(value)
      discord.webhook_url = value
    end

    # Access (or lazily create) the config for any provider name,
    # including future/custom providers:
    #   config.for(:sms).enabled = true
    def for(name)
      key = name.to_sym
      case key
      when :slack then slack
      when :email then email
      when :webhook then webhook
      when :discord then discord
      when :whatsapp then whatsapp
      else
        @custom[key] ||= ProviderConfig.new
      end
    end
    alias provider for

    # All provider configs keyed by name, including custom ones.
    def providers
      { slack: slack, email: email, webhook: webhook,
        discord: discord, whatsapp: whatsapp }.merge(@custom)
    end

    def enabled?
      !!@enabled
    end
  end
end
