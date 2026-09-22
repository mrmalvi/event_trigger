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
    #
    # NOTE: `config[:key]` reads raw options without hitting Ruby's own
    # methods (e.g. `config.method` would call Object#method, so use
    # `config[:method]` for the webhook HTTP verb).
    def [](key)
      @options[safe_key(key)]
    end

    def []=(key, value)
      @options[safe_key(key)] = value
    end

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

    private

    # Never let a non-symbolizable key raise (e.g. Integer keys).
    def safe_key(key)
      key.respond_to?(:to_sym) ? key.to_sym : key.to_s.to_sym
    rescue StandardError
      key.to_s
    end
  end

  # Global configuration object yielded by EventTrigger.configure.
  class Configuration
    # Hard safety net: no provider call may hang a host app forever.
    # 0 (or nil) disables the timeout. Per-provider override:
    #   config.slack.delivery_timeout = 5
    DEFAULT_DELIVERY_TIMEOUT = 15
    # Handlers are NOT time-limited by default (0 = disabled) because a
    # killed handler could leave partial work behind. Set to enable.
    DEFAULT_HANDLER_TIMEOUT = 0

    attr_accessor :enabled, :logger, :delivery_timeout, :handler_timeout
    attr_reader :slack, :email, :webhook, :discord, :whatsapp, :telegram, :teams, :sms

    # Backwards-compatible top-level shortcuts required by the spec:
    #   config.slack_webhook_url = ENV["SLACK_WEBHOOK_URL"]
    #   config.email_from = ENV["EVENT_TRIGGER_EMAIL_FROM"]
    # They delegate to the per-provider configs.
    def initialize
      @enabled = true
      @logger = nil
      @delivery_timeout = DEFAULT_DELIVERY_TIMEOUT
      @handler_timeout = DEFAULT_HANDLER_TIMEOUT
      @slack = ProviderConfig.new
      @email = ProviderConfig.new
      @webhook = ProviderConfig.new
      @discord = ProviderConfig.new
      @whatsapp = ProviderConfig.new
      @telegram = ProviderConfig.new
      @teams = ProviderConfig.new
      @sms = ProviderConfig.new
      @custom = {}
    end

    # Effective timeout for one provider (per-provider wins, then global).
    def timeout_for(provider_config)
      per_provider = begin
        provider_config[:delivery_timeout]
      rescue StandardError
        nil
      end
      value = per_provider.nil? ? @delivery_timeout : per_provider
      value.nil? ? DEFAULT_DELIVERY_TIMEOUT : value.to_f
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
      when :telegram then telegram
      when :teams then teams
      when :sms then sms
      else
        @custom[key] ||= ProviderConfig.new
      end
    end
    alias provider for

    # All provider configs keyed by name, including custom ones.
    # Order here is the dispatch order (existing providers first so
    # old result hashes keep their key order for backwards compat).
    def providers
      { slack: slack, email: email, webhook: webhook,
        discord: discord, whatsapp: whatsapp,
        telegram: telegram, teams: teams, sms: sms }.merge(@custom)
    end

    def enabled?
      !!@enabled
    end
  end
end
