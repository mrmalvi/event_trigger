# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Provider enable/disable + global switch" do
  let(:slack_class) { EventTrigger::Providers::SlackProvider }
  let(:email_class) { EventTrigger::Providers::EmailProvider }
  let(:webhook_class) { EventTrigger::Providers::WebhookProvider }

  it "executes only enabled providers" do
    slack = double("slack")
    email = double("email")
    allow(slack).to receive(:deliver).and_return(true)
    allow(email).to receive(:deliver).and_return(true)
    allow(slack_class).to receive(:new).and_return(slack)
    allow(email_class).to receive(:new).and_return(email)

    EventTrigger.configure do |c|
      c.enabled = true
      c.slack.enabled = true
      c.email.enabled = false
      c.webhook.enabled = false
    end

    EventTrigger.trigger("loan.activated", data: { loan_id: 1 })

    expect(slack).to have_received(:deliver)
    expect(email).not_to have_received(:deliver)
  end

  it "runs nothing when globally disabled (config.enabled = false)" do
    slack = double("slack")
    allow(slack).to receive(:deliver).and_return(true)
    allow(slack_class).to receive(:new).and_return(slack)

    EventTrigger.configure do |c|
      c.enabled = false
      c.slack.enabled = true
    end

    EventTrigger.trigger("loan.activated", data: {})

    expect(slack).not_to have_received(:deliver)
    expect(slack_class).not_to have_received(:new)
  end

  it "runs providers again after re-enabling globally" do
    slack = double("slack")
    allow(slack).to receive(:deliver).and_return(true)
    allow(slack_class).to receive(:new).and_return(slack)

    EventTrigger.configure do |c|
      c.enabled = false
      c.slack.enabled = true
    end
    EventTrigger.trigger("loan.activated", data: {})
    expect(slack).not_to have_received(:deliver)

    EventTrigger.configure { |c| c.enabled = true }
    EventTrigger.trigger("loan.activated", data: {})
    expect(slack).to have_received(:deliver).once
  end

  it "supports all three built-in providers toggled via config" do
    EventTrigger.configure do |c|
      c.enabled = true
      c.slack.enabled = true
      c.email.enabled = false
      c.webhook.enabled = true
    end

    expect(EventTrigger.configuration.slack.enabled).to be true
    expect(EventTrigger.configuration.email.enabled).to be false
    expect(EventTrigger.configuration.webhook.enabled).to be true
  end

  it "supports top-level legacy shortcuts (slack_webhook_url / email_from)" do
    EventTrigger.configure do |c|
      c.slack_webhook_url = "https://hooks.slack.com/x"
      c.email_from = "no-reply@example.com"
      c.enabled = true
    end

    expect(EventTrigger.configuration.slack.webhook_url).to eq("https://hooks.slack.com/x")
    expect(EventTrigger.configuration.email.from).to eq("no-reply@example.com")
  end
end
