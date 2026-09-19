# frozen_string_literal: true

module EventTrigger
  # Maps symbolic provider names (:slack, :email, :webhook, custom...)
  # to provider classes. Custom providers register via
  # EventTrigger.register_provider(:name, Klass).
  module Registry
    @providers = {}

    class << self
      def register(name, klass)
        @providers[name.to_sym] = klass
      end

      def fetch(name)
        @providers[name.to_sym]
      end

      def all
        @providers.dup
      end

      def registered?(name)
        @providers.key?(name.to_sym)
      end

      # Restore the five built-in providers (used by reset!).
      def reset!
        @providers = {}
        require_relative "providers/slack_provider"
        require_relative "providers/email_provider"
        require_relative "providers/webhook_provider"
        require_relative "providers/discord_provider"
        require_relative "providers/whatsapp_provider"
        register(:slack, Providers::SlackProvider)
        register(:email, Providers::EmailProvider)
        register(:webhook, Providers::WebhookProvider)
        register(:discord, Providers::DiscordProvider)
        register(:whatsapp, Providers::WhatsappProvider)
      end
    end
  end

  Registry.reset!
end
