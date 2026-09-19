# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Provider failure isolation" do
  let(:slack_class) { EventTrigger::Providers::SlackProvider }
  let(:email_class) { EventTrigger::Providers::EmailProvider }
  let(:webhook_class) { EventTrigger::Providers::WebhookProvider }

  before do
    EventTrigger.configure do |c|
      c.enabled = true
      c.slack.enabled = true
      c.email.enabled = true
      c.webhook.enabled = true
      c.slack.events = ["loan.activated"]
      c.email.events = ["loan.activated"]
      c.webhook.events = ["loan.activated"]
    end
  end

  it "Email still executes when Slack fails" do
    slack = double("slack")
    email = double("email")
    webhook = double("webhook")
    allow(slack).to receive(:deliver).and_raise(StandardError, "slack down")
    allow(email).to receive(:deliver).and_return(true)
    allow(webhook).to receive(:deliver).and_return(true)
    allow(slack_class).to receive(:new).and_return(slack)
    allow(email_class).to receive(:new).and_return(email)
    allow(webhook_class).to receive(:new).and_return(webhook)

    expect { EventTrigger.trigger("loan.activated", data: {}) }.not_to raise_error
    expect(email).to have_received(:deliver)
    expect(webhook).to have_received(:deliver)
  end

  it "all providers run even when every provider fails (errors are swallowed)" do
    [slack_class, email_class, webhook_class].each do |klass|
      inst = double(klass.name)
      allow(inst).to receive(:deliver).and_raise(StandardError, "down")
      allow(klass).to receive(:new).and_return(inst)
    end

    expect { EventTrigger.trigger("loan.activated", data: {}) }.not_to raise_error
  end

  it "a failing handler does not prevent other handlers or providers from running" do
    slack = double("slack")
    allow(slack).to receive(:deliver).and_return(true)
    allow(slack_class).to receive(:new).and_return(slack)
    allow(email_class).to receive(:new).and_raise("should not be called") # email subscribed but disabled below
    EventTrigger.configure { |c| c.email.enabled = false; c.webhook.enabled = false }

    calls = []
    EventTrigger.on("loan.activated") { |_e| raise "handler boom" }
    EventTrigger.on("loan.activated") { |_e| calls << :second }

    expect { EventTrigger.trigger("loan.activated", data: {}) }.not_to raise_error
    expect(calls).to eq([:second])
    expect(slack).to have_received(:deliver)
  end

  it "unknown provider names are skipped without crashing" do
    EventTrigger.configure do |c|
      c.for(:sms).enabled = true # no class registered for :sms
    end
    slack = double("slack")
    allow(slack).to receive(:deliver).and_return(true)
    allow(slack_class).to receive(:new).and_return(slack)

    expect { EventTrigger.trigger("loan.activated", data: {}) }.not_to raise_error
    expect(slack).to have_received(:deliver)
  end

  it "custom providers can be registered and participate in isolation" do
    custom_class = Class.new(EventTrigger::Provider) do
      def self.provider_name
        :sms
      end

      def deliver(event)
        raise "sms down"
      end
    end
    EventTrigger.register_provider(:sms, custom_class)
    EventTrigger.configure { |c| c.for(:sms).enabled = true }

    slack = double("slack")
    allow(slack).to receive(:deliver).and_return(true)
    allow(slack_class).to receive(:new).and_return(slack)

    expect { EventTrigger.trigger("loan.activated", data: {}) }.not_to raise_error
    expect(slack).to have_received(:deliver)
  end
end
