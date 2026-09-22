# frozen_string_literal: true

# Default EventTrigger configuration for your Rails app.
# Auto-created by the gem on first boot (and by `rails generate event_trigger:install`).
# Adjust values for your environment.

EventTrigger.configure do |config|
  config.enabled = true
  # Optional logging (defaults to Rails.logger via the gem Railtie).
  # Set to nil to silence, or Logger.new($stdout) for plain Ruby.
  # config.logger = Rails.logger

  config.slack.enabled = true
  config.slack.webhook_url = ENV["SLACK_WEBHOOK_URL"]
  # Allow-list of events for this provider. nil (or []) = ALL events.
  # Replace the examples below with your own event names.
  config.slack.events = ["loan.activated", "loan.overdue", "payment.received"]

  config.email.enabled = false
  config.email.from = ENV["EVENT_TRIGGER_EMAIL_FROM"]
  config.email.to = ENV["EVENT_TRIGGER_EMAIL_TO"]
  # Rails apps: uncomment so delivery goes through ActionMailer
  # (which uses config.action_mailer.smtp_settings below).
  # config.email.delivery_method = :action_mailer
  # nil (or []) = ALL events.
  config.email.events = ["loan.activated", "loan.foreclosed"]

  # --- ActionMailer SMTP (Rails) ---
  # Uncomment and move these lines to config/environments/development.rb
  # (and production.rb). Requires `gem "net-smtp"` on Ruby 3.1+.
  # config.action_mailer.delivery_method = :smtp
  # config.action_mailer.smtp_settings = {
  #   address: ENV.fetch("SMTP_ADDRESS", "smtp.gmail.com"),
  #   port: ENV.fetch("SMTP_PORT", "587").to_i,
  #   domain: ENV.fetch("SMTP_DOMAIN", "gmail.com"),
  #   user_name: ENV["SMTP_USERNAME"],
  #   password: ENV["SMTP_PASSWORD"]&.delete(" "),
  #   authentication: :plain,
  #   enable_starttls_auto: true
  # }
  # .env entries needed:
  # SMTP_USERNAME=youremail@gmail.com
  # SMTP_PASSWORD=xxxx xxxx xxxx xxxx   # Gmail App Password (16 letters), not your login password

  config.webhook.enabled = false
  config.webhook.url = ENV["EVENT_TRIGGER_WEBHOOK_URL"]
  # NOTE: `method` collides with Ruby's Object#method, so set it via []:
  # config.webhook[:method] = :post   # :post (default) | :put | :patch | :delete | :get
  # nil (or []) = ALL events.
  config.webhook.events = ["loan.activated"]

  config.discord.enabled = false
  config.discord.webhook_url = ENV["DISCORD_WEBHOOK_URL"]
  # nil (or []) = ALL events.
  config.discord.events = []

  config.whatsapp.enabled = false
  config.whatsapp.twilio_sid = ENV["TWILIO_ACCOUNT_SID"]
  config.whatsapp.twilio_token = ENV["TWILIO_AUTH_TOKEN"]
  config.whatsapp.twilio_from = ENV["TWILIO_WHATSAPP_FROM"]
  config.whatsapp.twilio_to = ENV["TWILIO_WHATSAPP_TO"]
  # nil (or []) = ALL events.
  config.whatsapp.events = []

  # --- NEW providers (opt-in; all default to disabled) ---
  config.telegram.enabled = false
  config.telegram.bot_token = ENV["TELEGRAM_BOT_TOKEN"]
  config.telegram.chat_id = ENV["TELEGRAM_CHAT_ID"]
  # nil (or []) = ALL events.
  config.telegram.events = []

  config.teams.enabled = false
  config.teams.access_token = ENV["TEAMS_ACCESS_TOKEN"]
  config.teams.team_id = ENV["TEAMS_TEAM_ID"]
  config.teams.channel_id = ENV["TEAMS_CHANNEL_ID"]
  # nil (or []) = ALL events.
  config.teams.events = []

  config.sms.enabled = false
  config.sms.provider = :twilio
  config.sms.account_sid = ENV["TWILIO_ACCOUNT_SID"]
  config.sms.auth_token = ENV["TWILIO_AUTH_TOKEN"]
  config.sms.from = ENV["TWILIO_FROM"]
  # nil (or []) = ALL events.
  config.sms.events = []
end
