# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Event-specific provider configuration" do
  let(:slack_class) { EventTrigger::Providers::SlackProvider }
  let(:email_class) { EventTrigger::Providers::EmailProvider }

  def stub_providers
    slack = double("slack")
    email = double("email")
    allow(slack).to receive(:deliver).and_return(true)
    allow(email).to receive(:deliver).and_return(true)
    allow(slack_class).to receive(:new).and_return(slack)
    allow(email_class).to receive(:new).and_return(email)
    [slack, email]
  end

  before do
    EventTrigger.configure do |c|
      c.enabled = true
      c.slack.enabled = true
      c.slack.events = ["loan.activated", "loan.overdue", "payment.received"]
      c.email.enabled = true
      c.email.events = ["loan.activated", "loan.foreclosed"]
      c.webhook.enabled = false
    end
  end

  it "runs Slack + Email for loan.activated" do
    slack, email = stub_providers
    EventTrigger.trigger("loan.activated", data: { loan_id: 1 })
    expect(slack).to have_received(:deliver)
    expect(email).to have_received(:deliver)
  end

  it "runs Slack but NOT Email for loan.overdue" do
    slack, email = stub_providers
    EventTrigger.trigger("loan.overdue", data: { loan_id: 2 })
    expect(slack).to have_received(:deliver)
    expect(email).not_to have_received(:deliver)
  end

  it "runs Email but NOT Slack for loan.foreclosed" do
    slack, email = stub_providers
    EventTrigger.trigger("loan.foreclosed", data: { loan_id: 3 })
    expect(slack).not_to have_received(:deliver)
    expect(email).to have_received(:deliver)
  end

  it "runs neither for an unlisted event" do
    slack, email = stub_providers
    EventTrigger.trigger("customer.created", data: {})
    expect(slack).not_to have_received(:deliver)
    expect(email).not_to have_received(:deliver)
  end

  it "nil events list means subscribed to ALL events" do
    slack, email = stub_providers
    EventTrigger.configure do |c|
      c.slack.events = nil
      c.email.events = nil
    end
    EventTrigger.trigger("anything.happens", data: {})
    expect(slack).to have_received(:deliver)
    expect(email).to have_received(:deliver)
  end

  it "disabled provider never runs even when subscribed to the event" do
    slack, email = stub_providers
    EventTrigger.configure { |c| c.email.enabled = false }
    EventTrigger.trigger("loan.activated", data: {})
    expect(slack).to have_received(:deliver)
    expect(email).not_to have_received(:deliver)
  end
end
