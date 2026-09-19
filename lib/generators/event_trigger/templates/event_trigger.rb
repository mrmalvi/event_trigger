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
  # nil (or []) = ALL events.
  config.email.events = ["loan.activated", "loan.foreclosed"]

  config.webhook.enabled = false
  config.webhook.url = ENV["EVENT_TRIGGER_WEBHOOK_URL"]
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
end
