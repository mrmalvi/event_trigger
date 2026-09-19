# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe EventTrigger::Providers::SlackProvider do
  def build_config(extra = {})
    config = EventTrigger::ProviderConfig.new(enabled: true)
    config.webhook_url = "https://hooks.slack.com/services/T/B/X"
    extra.each { |k, v| config.public_send("#{k}=", v) }
    config
  end

  def global_config
    EventTrigger.configuration
  end

  it "posts { text: ... } to Slack incoming webhooks (hooks.slack.com)" do
    provider = described_class.new(config: build_config, global_config: global_config)
    captured = nil
    allow(provider).to receive(:post_json) { |_url, body| captured = body }
    event = EventTrigger::Event.new(name: "loan.activated", payload: { loan_id: 123 })

    provider.deliver(event)

    expect(captured).to include(:text)
    expect(captured[:text]).to include("loan.activated")
  end

  it "formats error/backtrace payloads for Slack text" do
    provider = described_class.new(config: build_config, global_config: global_config)
    captured = nil
    allow(provider).to receive(:post_json) { |_url, body| captured = body }
    event = EventTrigger::Event.new(
      name: "error",
      payload: { error: "Boom", backtrace: ["line1", "line2"] }
    )

    provider.deliver(event)

    expect(captured[:text]).to include("Boom")
    expect(captured[:text]).to include("line1")
  end

  it "posts Discord-style embeds for non-Slack webhook URLs" do
    config = build_config
    config.webhook_url = "https://discord.com/api/webhooks/123/abc"
    provider = described_class.new(config: config, global_config: global_config)
    captured = nil
    allow(provider).to receive(:post_json) { |_url, body| captured = body }
    event = EventTrigger::Event.new(
      name: "error",
      payload: { error: "Boom", backtrace: ["a", "b"], context: { user: 1 } }
    )

    provider.deliver(event)

    expect(captured[:username]).to eq("RailsErrorNotifier")
    embed = captured[:embeds].first
    expect(embed[:title]).to include("Error")
    field_names = embed[:fields].map { |f| f[:name] }
    expect(field_names).to include("Backtrace", "Context")
    expect(JSON.generate(captured)).to be_a(String)
  end

  it "raises a clear error when webhook_url is missing" do
    config = EventTrigger::ProviderConfig.new(enabled: true)
    provider = described_class.new(config: config, global_config: global_config)
    event = EventTrigger::Event.new(name: "loan.activated", payload: {})
    expect { provider.deliver(event) }.to raise_error(EventTrigger::Error, /webhook_url/)
  end

  it "triggers end-to-end (loan.activated -> Slack runs)" do
    posted = nil
    allow_any_instance_of(described_class).to receive(:post_json) do |_inst, _url, body|
      posted = body
      double(code: "200")
    end
    EventTrigger.configure do |c|
      c.enabled = true
      c.slack.enabled = true
      c.slack.webhook_url = "https://hooks.slack.com/x"
      c.slack.events = ["loan.activated"]
      c.email.enabled = false
      c.webhook.enabled = false
    end

    EventTrigger.trigger("loan.activated", data: { loan_id: 123, customer_name: "Kamlesh" })

    expect(posted).not_to be_nil
  end
end
