# frozen_string_literal: true

require "spec_helper"

RSpec.describe EventTrigger::Providers::WhatsappProvider do
  def build_config(extra = {})
    config = EventTrigger::ProviderConfig.new(enabled: true)
    config.twilio_sid = "AC123"
    config.twilio_token = "tok"
    config.twilio_from = "whatsapp:+14155238886"
    config.twilio_to = "whatsapp:+919876543210"
    extra.each { |k, v| config.public_send("#{k}=", v) }
    config
  end

  # Fake Twilio client — no network, no gem required for these specs.
  class FakeMessages
    attr_reader :params

    def create(params)
      @params = params
      { "sid" => "SM123" }
    end
  end

  class FakeTwilioClient
    attr_reader :messages

    def initialize(*_args)
      @messages = FakeMessages.new
    end
  end

  before do
    stub_const("Twilio::REST::Client", FakeTwilioClient)
  end

  it "sends RailsErrorNotifier-style message via Twilio" do
    provider = described_class.new(config: build_config, global_config: EventTrigger.configuration)
    client = nil
    allow(FakeTwilioClient).to receive(:new).and_wrap_original do |m, *args|
      client = m.call(*args)
      client
    end
    event = EventTrigger::Event.new(
      name: "app.error",
      payload: { error: "Boom", backtrace: ["line1", "line2"], context: { user: 1 } }
    )
    expect(provider.deliver(event)).to be true
    expect(client.messages.params[:from]).to eq("whatsapp:+14155238886")
    expect(client.messages.params[:to]).to eq("whatsapp:+919876543210")
    expect(client.messages.params[:body]).to include("Boom")
    expect(client.messages.params[:body]).to include("line1")
  end

  it "supports per-trigger whatsapp_to override" do
    provider = described_class.new(config: build_config, global_config: EventTrigger.configuration)
    client = nil
    allow(FakeTwilioClient).to receive(:new).and_wrap_original do |m, *args|
      client = m.call(*args)
      client
    end
    event = EventTrigger::Event.new(name: "x", payload: { whatsapp_to: "+91111" })
    provider.deliver(event)
    expect(client.messages.params[:to]).to eq("whatsapp:+91111")
  end

  it "normalizes numbers missing the whatsapp: scheme" do
    provider = described_class.new(config: build_config(twilio_to: "+91999"), global_config: EventTrigger.configuration)
    client = nil
    allow(FakeTwilioClient).to receive(:new).and_wrap_original do |m, *args|
      client = m.call(*args)
      client
    end
    provider.deliver(EventTrigger::Event.new(name: "x", payload: {}))
    expect(client.messages.params[:to]).to eq("whatsapp:+91999")
  end

  it "raises clear errors for missing credentials (logged, never crashes app)" do
    event = EventTrigger::Event.new(name: "x", payload: {})
    %i[twilio_sid twilio_token twilio_from twilio_to].each do |key|
      cfg = build_config(key => nil)
      # `to` can also come from whatsapp_to; keep payload empty so it errors.
      provider = described_class.new(config: cfg, global_config: EventTrigger.configuration)
      expect { provider.deliver(event) }.to raise_error(EventTrigger::Error)
    end
  end

  it "missing twilio gem raises a clear error instead of NameError" do
    provider = described_class.new(config: build_config, global_config: EventTrigger.configuration)
    expect(provider).to receive(:twilio_client_class).and_return(nil)
    expect { provider.deliver(EventTrigger::Event.new(name: "x", payload: {})) }
      .to raise_error(EventTrigger::Error, /twilio-ruby/)
  end

  it "a crashing whatsapp provider never blocks other providers" do
    EventTrigger.configure do |c|
      c.enabled = true
      c.slack.enabled = true
      c.whatsapp.enabled = true
      c.email.enabled = false
      c.webhook.enabled = false
      c.discord.enabled = false
    end
    allow_any_instance_of(described_class).to receive(:deliver).and_raise(StandardError, "twilio down")
    slack = double("slack")
    allow(slack).to receive(:deliver).and_return(true)
    allow(EventTrigger::Providers::SlackProvider).to receive(:new).and_return(slack)

    expect { EventTrigger.trigger("app.error", data: { error: "x" }) }.not_to raise_error
    expect(slack).to have_received(:deliver)
  end
end
