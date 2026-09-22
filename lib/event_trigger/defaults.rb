# frozen_string_literal: true

module EventTrigger
  # Default configuration applied when the gem is bundled into an app.
  #
  # Runs via the Railtie BEFORE the host app's initializers, so a
  # user-provided config/initializers/event_trigger.rb can override
  # anything set here. It also means the gem works out-of-the-box with
  # zero configuration: this exact block is the default.
  #
  #   EventTrigger.configure do |config|
  #     config.enabled = true
  #     config.slack.enabled = true
  #     config.slack.webhook_url = ENV["SLACK_WEBHOOK_URL"]
  #     config.slack.events = ["loan.activated", "loan.overdue", "payment.received"]
  #     config.email.enabled = false
  #     config.email.from = ENV["EVENT_TRIGGER_EMAIL_FROM"]
  #     ...
  #   end
  # Never raises: called from the Railtie at boot time.
  def self.apply_defaults!(logger: nil)
    configure do |config|
      config.enabled = true
      config.logger ||= logger

      config.slack.enabled = true
      config.slack.webhook_url ||= ENV["SLACK_WEBHOOK_URL"]
      config.slack.events = ["loan.activated", "loan.overdue", "payment.received"]

      config.email.enabled = false
      config.email.from ||= ENV["EVENT_TRIGGER_EMAIL_FROM"]
      config.email.to ||= ENV["EVENT_TRIGGER_EMAIL_TO"] || "ops@example.com"
      config.email.events = ["loan.activated", "loan.foreclosed"]

      config.webhook.enabled = false
      config.webhook.url ||= ENV["EVENT_TRIGGER_WEBHOOK_URL"]
      # Leave webhook subscribed to nothing until the app opts in.
      config.webhook.events ||= []

      config.discord.enabled = false
      config.discord.webhook_url ||= ENV["DISCORD_WEBHOOK_URL"]
      config.discord.events ||= []

      config.whatsapp.enabled = false
      config.whatsapp.twilio_sid ||= ENV["TWILIO_ACCOUNT_SID"]
      config.whatsapp.twilio_token ||= ENV["TWILIO_AUTH_TOKEN"]
      config.whatsapp.twilio_from ||= ENV["TWILIO_WHATSAPP_FROM"]
      config.whatsapp.twilio_to ||= ENV["TWILIO_WHATSAPP_TO"]
      config.whatsapp.events ||= []

      # NEW providers default to disabled + unsubscribed; enabling them
      # is purely opt-in so existing apps see no behaviour change.
      config.telegram.enabled = false
      config.telegram.bot_token ||= ENV["TELEGRAM_BOT_TOKEN"]
      config.telegram.chat_id ||= ENV["TELEGRAM_CHAT_ID"]
      config.telegram.events ||= []

      config.teams.enabled = false
      config.teams.access_token ||= ENV["TEAMS_ACCESS_TOKEN"]
      config.teams.team_id ||= ENV["TEAMS_TEAM_ID"]
      config.teams.channel_id ||= ENV["TEAMS_CHANNEL_ID"]
      config.teams.events ||= []

      config.sms.enabled = false
      config.sms.provider ||= :twilio
      config.sms.account_sid ||= ENV["TWILIO_ACCOUNT_SID"]
      config.sms.auth_token ||= ENV["TWILIO_AUTH_TOKEN"]
      config.sms.from ||= ENV["TWILIO_FROM"]
      config.sms.events ||= []
    end
  rescue StandardError
    nil
  end
end
