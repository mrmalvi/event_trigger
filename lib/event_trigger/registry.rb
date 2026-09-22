# frozen_string_literal: true

module EventTrigger
  # Maps symbolic provider names (:slack, :email, :webhook, custom...)
  # to provider classes. Custom providers register via
  # EventTrigger.register_provider(:name, Klass).
  module Registry
    @providers = {}

    class << self
      def register(name, klass)
        EventTrigger.lock.synchronize { @providers[name.to_sym] = klass }
      rescue StandardError
        nil
      end

      def fetch(name)
        @providers[name.to_sym]
      rescue StandardError
        nil
      end

      def all
        @providers.dup
      rescue StandardError
        {}
      end

      def registered?(name)
        @providers.key?(name.to_sym)
      rescue StandardError
        false
      end

      # Restore the eight built-in providers (used by reset!).
      def reset!
        @providers = {}
        require_relative "providers/slack_provider"
        require_relative "providers/email_provider"
        require_relative "providers/webhook_provider"
        require_relative "providers/discord_provider"
        require_relative "providers/whatsapp_provider"
        require_relative "providers/telegram_provider"
        require_relative "providers/teams_provider"
        require_relative "providers/sms_provider"
        register(:slack, Providers::SlackProvider)
        register(:email, Providers::EmailProvider)
        register(:webhook, Providers::WebhookProvider)
        register(:discord, Providers::DiscordProvider)
        register(:whatsapp, Providers::WhatsappProvider)
        register(:telegram, Providers::TelegramProvider)
        register(:teams, Providers::TeamsProvider)
        register(:sms, Providers::SmsProvider)
      end
    end
  end

  Registry.reset!
end
