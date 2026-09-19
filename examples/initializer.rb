# frozen_string_literal: true

# Sample Rails initializer for EventTrigger.
# Copy to your app as config/initializers/event_trigger.rb
# and adjust values for your environment.

EventTrigger.configure do |config|
  config.enabled = true

  config.slack.enabled = true
  config.slack.webhook_url = ENV["SLACK_WEBHOOK_URL"]
  config.slack.events = %w[
    loan.activated
    loan.overdue
    payment.received
  ]

  config.email.enabled = false
  config.email.from = ENV["EVENT_TRIGGER_EMAIL_FROM"]
  config.email.to = ENV["EVENT_TRIGGER_EMAIL_TO"]
  config.email.events = %w[
    loan.activated
    loan.foreclosed
  ]

  config.webhook.enabled = false
  # config.webhook.url = ENV["EVENT_TRIGGER_WEBHOOK_URL"]
  # config.webhook.events = %w[loan.activated]

  # Optional logging (defaults to no logging):
  # config.logger = Rails.logger
end
