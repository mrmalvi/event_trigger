# frozen_string_literal: true

require "spec_helper"

RSpec.describe EventTrigger::Providers::DiscordProvider do
  def build_config(extra = {})
    config = EventTrigger::ProviderConfig.new(enabled: true)
    config.webhook_url = "https://discord.com/api/webhooks/123/abc"
    extra.each { |k, v| config.public_send("#{k}=", v) }
    config
  end

  it "posts the RailsErrorNotifier-style embed payload" do
    provider = described_class.new(config: build_config, global_config: EventTrigger.configuration)
    captured_url = nil
    captured = nil
    allow(provider).to receive(:post_json) do |url, body, *_args|
      captured_url = url
      captured = body
      double(code: "200")
    end

    event = EventTrigger::Event.new(
      name: "app.error",
      payload: { error: "Boom", backtrace: ["a", "b"], context: { user: 1 } }
    )
    expect(provider.deliver(event)).to be true

    expect(captured_url).to include("discord.com")
    expect(captured[:username]).to eq("RailsErrorNotifier")
    embed = captured[:embeds].first
    expect(embed[:title]).to include("Error")
    expect(embed[:description]).to include("Boom")
    names = embed[:fields].map { |f| f[:name] }
    expect(names).to include("Backtrace", "Context")
  end

  it "truncates long backtrace/context like the reference notifier" do
    provider = described_class.new(config: build_config, global_config: EventTrigger.configuration)
    captured = nil
    allow(provider).to receive(:post_json) { |_u, body, *_a| captured = body }
    long = "x" * 5000
    event = EventTrigger::Event.new(
      name: "app.error",
      payload: { error: "Boom", backtrace: [long], context: { big: long } }
    )
    provider.deliver(event)
    fields = captured[:embeds].first[:fields]
    fields.each do |f|
      # ```\n + ~1014 chars + \n``` stays well under Discord limits
      expect(f[:value].length).to be < 1500
    end
  end

  it "raises a clear error when webhook_url is missing" do
    provider = described_class.new(
      config: EventTrigger::ProviderConfig.new(enabled: true),
      global_config: EventTrigger.configuration
    )
    event = EventTrigger::Event.new(name: "app.error", payload: {})
    expect { provider.deliver(event) }.to raise_error(EventTrigger::Error, /webhook_url/)
  end

  it "dispatches end-to-end only when enabled + subscribed" do
    posted = nil
    allow_any_instance_of(described_class).to receive(:post_json) do |_i, _u, body, *_a|
      posted = body
      double(code: "200")
    end
    EventTrigger.configure do |c|
      c.enabled = true
      c.slack.enabled = false
      c.email.enabled = false
      c.webhook.enabled = false
      c.discord.enabled = true
      c.discord.webhook_url = "https://discord.com/api/webhooks/1/2"
      c.discord.events = ["app.error"]
      c.whatsapp.enabled = false
    end
    EventTrigger.trigger("app.error", data: { error: "Boom" })
    expect(posted).not_to be_nil
    posted = nil
    EventTrigger.trigger("other.event", data: {})
    expect(posted).to be_nil
  end
end
