# frozen_string_literal: true

require "spec_helper"

RSpec.describe "EventTrigger.apply_defaults!" do
  it "applies the documented default configuration block" do
    EventTrigger.apply_defaults!

    config = EventTrigger.configuration
    expect(config.enabled).to be true

    expect(config.slack.enabled).to be true
    expect(config.slack.events).to eq(["loan.activated", "loan.overdue", "payment.received"])

    expect(config.email.enabled).to be false
    expect(config.email.events).to eq(["loan.activated", "loan.foreclosed"])

    expect(config.webhook.enabled).to be false
  end

  it "picks webhook_url / email_from from ENV when present" do
    orig_slack = ENV["SLACK_WEBHOOK_URL"]
    orig_email = ENV["EVENT_TRIGGER_EMAIL_FROM"]
    ENV["SLACK_WEBHOOK_URL"] = "https://hooks.slack.com/x"
    ENV["EVENT_TRIGGER_EMAIL_FROM"] = "from@example.com"
    begin
      EventTrigger.apply_defaults!
      expect(EventTrigger.configuration.slack.webhook_url).to eq("https://hooks.slack.com/x")
      expect(EventTrigger.configuration.email.from).to eq("from@example.com")
    ensure
      ENV["SLACK_WEBHOOK_URL"] = orig_slack
      ENV["EVENT_TRIGGER_EMAIL_FROM"] = orig_email
    end
  end

  it "explicit user configuration wins when applied after defaults" do
    EventTrigger.apply_defaults!
    EventTrigger.configure do |config|
      config.email.enabled = true
      config.email.from = "custom@example.com"
    end

    expect(EventTrigger.configuration.email.enabled).to be true
    expect(EventTrigger.configuration.email.from).to eq("custom@example.com")
    # Untouched defaults remain.
    expect(EventTrigger.configuration.slack.enabled).to be true
  end

  it "ships an install generator template matching the defaults" do
    template = File.read(
      File.expand_path("../lib/generators/event_trigger/templates/event_trigger.rb", __dir__)
    )
    expect(template).to include('config.slack.events = ["loan.activated", "loan.overdue", "payment.received"]')
    expect(template).to include('config.email.events = ["loan.activated", "loan.foreclosed"]')
    expect(template).to include("config.slack.enabled = true")
    expect(template).to include("config.email.enabled = false")
    expect(template).to include("config.webhook.enabled = false")
  end
end
