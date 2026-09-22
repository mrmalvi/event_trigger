# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "logger"

RSpec.describe "Configuration, logging, unknown handling, custom providers" do
  it "has sensible defaults (enabled globally, providers disabled)" do
    config = EventTrigger::Configuration.new
    expect(config.enabled).to be true
    expect(config.slack.enabled).to be false
    expect(config.email.enabled).to be false
    expect(config.webhook.enabled).to be false
  end

  it "ProviderConfig#subscribed_to? treats nil/empty as all events" do
    config = EventTrigger::ProviderConfig.new(enabled: true)
    expect(config.subscribed_to?("anything")).to be true
    config.events = []
    expect(config.subscribed_to?("anything")).to be true
    config.events = ["a"]
    expect(config.subscribed_to?("a")).to be true
    expect(config.subscribed_to?("b")).to be false
  end

  it "logs event triggered / executed / skipped / failed" do
    io = StringIO.new
    EventTrigger.configure do |c|
      c.enabled = true
      c.logger = Logger.new(io)
      c.slack.enabled = true
      c.slack.events = ["loan.activated"]
      c.email.enabled = false
      c.webhook.enabled = false
    end

    slack = double("slack")
    allow(slack).to receive(:deliver).and_return(true)
    allow(EventTrigger::Providers::SlackProvider).to receive(:new).and_return(slack)

    EventTrigger.trigger("loan.activated", data: { loan_id: 1 })
    log = io.string
    expect(log).to include("event triggered: loan.activated")
    expect(log).to include("provider ':slack' executed")
    expect(log).to include("provider ':email' skipped (disabled)")
  end

  it "logs provider failures but keeps going" do
    io = StringIO.new
    EventTrigger.configure do |c|
      c.enabled = true
      c.logger = Logger.new(io)
      c.slack.enabled = true
      c.email.enabled = true
    end

    slack = double("slack")
    email = double("email")
    allow(slack).to receive(:deliver).and_raise("boom")
    allow(email).to receive(:deliver).and_return(true)
    allow(EventTrigger::Providers::SlackProvider).to receive(:new).and_return(slack)
    allow(EventTrigger::Providers::EmailProvider).to receive(:new).and_return(email)

    EventTrigger.trigger("loan.activated", data: {})
    expect(io.string).to include("provider ':slack' failed")
    expect(email).to have_received(:deliver)
  end

  it "registering a custom provider makes it dispatchable via config.for" do
    klass = Class.new(EventTrigger::Provider) do
      def self.provider_name
        :pagerduty
      end

      def deliver(event)
        self.class.delivered_events << event
        true
      end

      def self.delivered_events
        @delivered_events ||= []
      end
    end
    EventTrigger.register_provider(:pagerduty, klass)

    expect(EventTrigger::Registry.registered?(:pagerduty)).to be true

    EventTrigger.configure do |c|
      c.enabled = true
      c.for(:pagerduty).enabled = true
      c.slack.enabled = false
      c.email.enabled = false
      c.webhook.enabled = false
    end

    EventTrigger.trigger("loan.activated", data: { x: 1 })
    expect(klass.delivered_events.map(&:name)).to eq(["loan.activated"])
  end

  it "reset! restores defaults and clears handlers" do
    EventTrigger.configure { |c| c.enabled = false }
    EventTrigger.on("x") { |_e| nil }
    EventTrigger.reset!
    expect(EventTrigger.configuration.enabled).to be true
    expect(EventTrigger.handlers_for("x")).to be_empty
  end

  it "unknown events with no providers configured do not raise" do
    EventTrigger.configure { |c| c.enabled = true }
    allow_any_instance_of(EventTrigger::Providers::SlackProvider).to receive(:deliver).and_return(true)
    expect { EventTrigger.trigger("never.seen.before", data: {}) }.not_to raise_error
  end

  it "WebhookProvider posts JSON event envelope" do
    config = EventTrigger::ProviderConfig.new(enabled: true)
    config.url = "https://example.com/hook"
    provider = EventTrigger::Providers::WebhookProvider.new(
      config: config, global_config: EventTrigger.configuration
    )
    captured = nil
    allow(provider).to receive(:request_json) { |_m, _url, body, _h, service: "HTTP"| captured = body }
    provider.deliver(EventTrigger::Event.new(name: "loan.activated", payload: { loan_id: 5 }))
    expect(captured[:event]).to eq("loan.activated")
    expect(captured[:payload]["loan_id"]).to eq(5)
  end
end
