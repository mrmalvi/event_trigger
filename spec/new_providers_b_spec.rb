# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SMS provider + email smtp alias + webhook method (additive)" do
  class FakeSmsMessages
    attr_reader :params

    def create(params)
      @params = params
      { "sid" => "SM1" }
    end
  end

  class FakeSmsClient
    attr_reader :messages

    def initialize(*_a)
      @messages = FakeSmsMessages.new
    end
  end

  before { stub_const("Twilio::REST::Client", FakeSmsClient) }

  it "sends SMS via Twilio with from/to/body" do
    EventTrigger.configure do |c|
      c.sms.enabled = true
      c.sms.provider = :twilio
      c.sms.account_sid = "AC1"
      c.sms.auth_token = "AT1"
      c.sms.from = "+1000"
      c.sms.events = ["payment.received"]
    end
    client = nil
    allow(FakeSmsClient).to receive(:new).and_wrap_original do |m, *a|
      client = m.call(*a)
      client
    end
    provider = EventTrigger::Providers::SmsProvider.new(
      config: EventTrigger.configuration.sms, global_config: EventTrigger.configuration
    )
    expect(provider.deliver(EventTrigger::Event.new(name: "payment.received", payload: { sms_to: "+2000" }))).to be true
    expect(client.messages.params[:from]).to eq("+1000")
    expect(client.messages.params[:to]).to eq("+2000")
  end

  it "rejects unknown sms providers and missing twilio gem" do
    EventTrigger.configure { |c| c.sms.provider = :other }
    provider = EventTrigger::Providers::SmsProvider.new(
      config: EventTrigger.configuration.sms, global_config: EventTrigger.configuration
    )
    expect { provider.deliver(EventTrigger::Event.new(name: "x", payload: {})) }
      .to raise_error(EventTrigger::Error, /not supported/)

    EventTrigger.configure { |c| c.sms.provider = :twilio }
    provider2 = EventTrigger::Providers::SmsProvider.new(
      config: EventTrigger.configuration.sms, global_config: EventTrigger.configuration
    )
    expect(provider2).to receive(:twilio_client_class).and_return(nil)
    expect { provider2.deliver(EventTrigger::Event.new(name: "x", payload: {})) }
      .to raise_error(EventTrigger::Error, /twilio-ruby/)
  end

  it "accepts config.email.smtp with string keys and username alias" do
    config = EventTrigger::ProviderConfig.new(enabled: true)
    config.from = "a@x.com"
    config.to = "b@x.com"
    config.smtp = { "address" => "smtp.x.com", "port" => 587, "username" => "u", "password" => "p" }
    provider = EventTrigger::Providers::EmailProvider.new(config: config, global_config: EventTrigger.configuration)

    settings_seen = nil
    allow(provider).to receive(:deliver_via_smtp) { |_f, _t, _s, _b| settings_seen = provider.__send__(:smtp_settings) }
    provider.deliver(EventTrigger::Event.new(name: "loan.activated", payload: {}))
    expect(settings_seen[:address]).to eq("smtp.x.com")
    expect(settings_seen[:port]).to eq(587)
    expect(settings_seen[:user_name]).to eq("u")
    expect(settings_seen[:password]).to eq("p")
  end

  it "webhook defaults to POST and normalizes custom verbs" do
    provider = EventTrigger::Providers::WebhookProvider.new(
      config: EventTrigger::ProviderConfig.new(enabled: true), global_config: EventTrigger.configuration
    )
    provider.config.url = "https://example.com/hook"
    seen = nil
    allow(provider).to receive(:request_json) { |m, *_a| seen = m; double(code: "200") }
    provider.deliver(EventTrigger::Event.new(name: "loan.activated", payload: {}))
    expect(seen).to eq(:post)
    provider.config[:method] = "PUT"
    provider.deliver(EventTrigger::Event.new(name: "loan.activated", payload: {}))
    expect(seen).to eq(:put)
    provider.config[:method] = :bogus
    provider.deliver(EventTrigger::Event.new(name: "loan.activated", payload: {}))
    expect(seen).to eq(:post)
  end
end
