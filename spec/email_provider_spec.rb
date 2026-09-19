# frozen_string_literal: true

require "spec_helper"

RSpec.describe EventTrigger::Providers::EmailProvider do
  def build_config(extra = {})
    config = EventTrigger::ProviderConfig.new(enabled: true)
    config.from = "no-reply@example.com"
    config.to = "ops@example.com"
    extra.each { |k, v| config.public_send("#{k}=", v) }
    config
  end

  it "delivers via SMTP with from/to/subject/body" do
    config = build_config
    provider = described_class.new(config: config, global_config: EventTrigger.configuration)
    event = EventTrigger::Event.new(name: "loan.activated", payload: { loan_id: 123 })

    smtp = double("smtp")
    allow(smtp).to receive(:send_message)
    allow(Net::SMTP).to receive(:start).and_yield(smtp)

    expect(provider.deliver(event)).to be true
    expect(Net::SMTP).to have_received(:start)
    expect(smtp).to have_received(:send_message) do |message, from, to|
      expect(from).to eq("no-reply@example.com")
      expect(to).to eq(["ops@example.com"])
      expect(message).to include("loan.activated")
      expect(message).to include("123")
    end
  end

  it "uses global email_from fallback and per-trigger email_to override" do
    EventTrigger.configure { |c| c.email_from = "global@example.com" }
    config = EventTrigger::ProviderConfig.new(enabled: true)
    provider = described_class.new(config: config, global_config: EventTrigger.configuration)
    event = EventTrigger::Event.new(
      name: "loan.activated",
      payload: { email_to: "user@example.com", loan_id: 1 }
    )

    smtp = double("smtp")
    allow(smtp).to receive(:send_message)
    allow(Net::SMTP).to receive(:start).and_yield(smtp)

    provider.deliver(event)

    expect(smtp).to have_received(:send_message) do |_msg, from, to|
      expect(from).to eq("global@example.com")
      expect(to).to eq(["user@example.com"])
    end
  end

  it "raises a clear error when from/to are missing" do
    config = EventTrigger::ProviderConfig.new(enabled: true)
    provider = described_class.new(config: config, global_config: EventTrigger.configuration)
    event = EventTrigger::Event.new(name: "loan.activated", payload: {})
    expect { provider.deliver(event) }.to raise_error(EventTrigger::Error, /from/i)
  end

  it "triggers end-to-end (loan.activated -> Email runs only if enabled)" do
    smtp = double("smtp")
    allow(smtp).to receive(:send_message)
    allow(Net::SMTP).to receive(:start).and_yield(smtp)

    EventTrigger.configure do |c|
      c.enabled = true
      c.slack.enabled = false
      c.webhook.enabled = false
      c.email.enabled = true
      c.email.from = "no-reply@example.com"
      c.email.to = "ops@example.com"
      c.email.events = ["loan.activated"]
    end
    EventTrigger.trigger("loan.activated", data: { loan_id: 1 })
    expect(smtp).to have_received(:send_message).once

    EventTrigger.configure { |c| c.email.enabled = false }
    EventTrigger.trigger("loan.overdue", data: { loan_id: 1 })
    # still exactly once -- disabled provider did not send again
    expect(smtp).to have_received(:send_message).once
  end
end
