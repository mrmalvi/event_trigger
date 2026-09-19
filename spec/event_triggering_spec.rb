# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Event triggering" do
  # Stub out network delivery so no real HTTP/SMTP happens.
  before do
    allow_any_instance_of(EventTrigger::Providers::SlackProvider).to receive(:deliver).and_return(true)
    allow_any_instance_of(EventTrigger::Providers::EmailProvider).to receive(:deliver).and_return(true)
    allow_any_instance_of(EventTrigger::Providers::WebhookProvider).to receive(:deliver).and_return(true)
  end

  it "returns an Event with the triggered name and payload" do
    EventTrigger.configure do |c|
      c.enabled = true
      c.slack.enabled = true
    end

    event = EventTrigger.trigger("loan.activated", data: { loan_id: 123, customer_name: "John" })

    expect(event).to be_a(EventTrigger::Event)
    expect(event.name).to eq("loan.activated")
    expect(event.payload[:loan_id]).to eq(123)
    expect(event.payload[:customer_name]).to eq("John")
  end

  it "accepts arbitrary payload data (anything can be sent in)" do
    EventTrigger.configure { |c| c.enabled = true }
    event = EventTrigger.trigger(
      "loan.activated",
      data: { loan_id: 123, customer_name: "Kamlesh", nested: { a: [1, 2] }, flag: true }
    )
    expect(event.payload[:nested]).to eq(a: [1, 2])
    expect(event.payload[:flag]).to be true
  end

  it "runs registered handlers with the event" do
    seen = []
    EventTrigger.on("loan.activated") { |e| seen << e.name }
    EventTrigger.trigger("loan.activated", data: { loan_id: 1 })
    expect(seen).to eq(["loan.activated"])
  end

  it "does not run handlers registered for other events" do
    seen = []
    EventTrigger.on("loan.overdue") { |_e| seen << :overdue }
    EventTrigger.trigger("loan.activated", data: {})
    expect(seen).to be_empty
  end

  it "supports multiple handlers for the same event" do
    calls = []
    EventTrigger.on("payment.received") { |_e| calls << 1 }
    EventTrigger.on("payment.received") { |_e| calls << 2 }
    EventTrigger.trigger("payment.received", data: {})
    expect(calls).to contain_exactly(1, 2)
  end

  it "handles unknown events gracefully (no providers crash)" do
    EventTrigger.configure do |c|
      c.enabled = true
      c.slack.enabled = true
      c.slack.events = ["loan.activated"]
    end
    expect { EventTrigger.trigger("some.unknown.event", data: { a: 1 }) }.not_to raise_error
  end

  it "symbol event names are normalized to strings" do
    seen = []
    EventTrigger.on("loan.activated") { |e| seen << e.name }
    EventTrigger.trigger(:"loan.activated", data: {})
    expect(seen).to eq(["loan.activated"])
  end

  it "off removes handlers" do
    EventTrigger.on("loan.activated") { |_e| raise "should not run" }
    EventTrigger.off("loan.activated")
    expect { EventTrigger.trigger("loan.activated", data: {}) }.not_to raise_error
  end
end
