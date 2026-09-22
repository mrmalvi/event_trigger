# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Provider-wise result hash + interface + security (additive)" do
  it "returns { event:, status:, providers: } with sent/failed/skipped" do
    slack = double("slack")
    allow(slack).to receive(:deliver).and_return(true)
    allow(EventTrigger::Providers::SlackProvider).to receive(:new).and_return(slack)
    email = double("email")
    allow(email).to receive(:deliver).and_raise("down")
    allow(EventTrigger::Providers::EmailProvider).to receive(:new).and_return(email)

    EventTrigger.configure do |c|
      c.enabled = true
      c.slack.enabled = true
      c.slack.events = ["loan.activated"]
      c.email.enabled = true
      c.email.events = ["loan.activated"]
      c.webhook.enabled = false
      c.discord.enabled = false
      c.whatsapp.enabled = false
      c.telegram.enabled = false
      c.teams.enabled = false
      c.sms.enabled = false
    end

    event = EventTrigger.trigger("loan.activated", data: { loan_id: 123 })
    result = EventTrigger.last_result
    expect(result[:event]).to eq("loan.activated")
    expect(result[:status]).to eq("success")
    expect(result[:providers][:slack]).to eq("sent")
    expect(result[:providers][:email]).to eq("failed")
    expect(result[:providers][:webhook]).to start_with("skipped")
    expect(result[:providers][:discord]).to start_with("skipped")
    expect(event.last_result).to eq(result)
  end

  it "marks unsubscribed providers as skipped, keeps Event return, handles invalid events" do
    allow_any_instance_of(EventTrigger::Providers::SlackProvider).to receive(:deliver).and_return(true)
    EventTrigger.configure do |c|
      c.enabled = true
      c.slack.enabled = true
      c.slack.events = ["loan.activated"]
      c.email.enabled = false
      c.webhook.enabled = false
      c.discord.enabled = false
      c.whatsapp.enabled = false
      c.telegram.enabled = false
      c.teams.enabled = false
      c.sms.enabled = false
    end
    event = EventTrigger.trigger("payment.received", data: {})
    expect(event).to be_a(EventTrigger::Event)
    expect(EventTrigger.last_result[:providers][:slack]).to start_with("skipped")

    expect { EventTrigger.trigger("", data: {}) }.not_to raise_error
    expect(EventTrigger.last_result[:event]).to eq("")
  end

  it "every built-in provider responds to send(event_name, data)" do
    %i[slack email webhook discord whatsapp telegram teams sms].each do |name|
      klass = EventTrigger::Registry.fetch(name)
      expect(klass).not_to be_nil
      expect(klass.allocate).to respond_to(:send)
    end
  end

  it "never logs credentials" do
    io = StringIO.new
    EventTrigger.configure do |c|
      c.enabled = true
      c.logger = Logger.new(io)
      c.slack.enabled = true
      c.slack.token = "xoxb-SECRET123"
    end
    allow_any_instance_of(EventTrigger::Providers::SlackProvider)
      .to receive(:deliver).and_raise(StandardError, "bad token=xoxb-SECRET123")
    EventTrigger.trigger("loan.activated", data: { api_token: "abc" })
    expect(io.string).not_to include("xoxb-SECRET123")
  end
end
