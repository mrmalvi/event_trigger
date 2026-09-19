# frozen_string_literal: true

# Plain-Ruby usage example (no Rails required).
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "event_trigger"
require "logger"

EventTrigger.configure do |config|
  config.enabled = true
  config.logger = Logger.new($stdout)

  config.slack.enabled = true
  config.slack.webhook_url = ENV["SLACK_WEBHOOK_URL"]
  config.slack.events = ["loan.activated", "loan.overdue", "payment.received"]

  config.email.enabled = false
  config.email.from = ENV["EVENT_TRIGGER_EMAIL_FROM"]
  config.email.to = "ops@example.com"
  config.email.events = ["loan.activated", "loan.foreclosed"]

  config.webhook.enabled = false
end

# Custom per-event logic alongside providers:
EventTrigger.on("loan.activated") do |event|
  puts "Custom handler saw loan #{event.payload[:loan_id]} for #{event.payload[:customer_name]}"
end

# Anything can be sent in `data:` -- it is passed through to providers/handlers.
EventTrigger.trigger(
  "loan.activated",
  data: {
    loan_id: 123,
    customer_name: "Kamlesh"
  }
)

# Error-style payload (Slack text vs Discord embed chosen automatically):
EventTrigger.trigger(
  "app.error",
  data: {
    error: "Something went wrong",
    backtrace: caller.first(5),
    context: { user_id: 42 }
  }
)
