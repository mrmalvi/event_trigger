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
    end
  end
end
