# frozen_string_literal: true

require "spec_helper"

RSpec.describe "New provider APIs (telegram / teams / sms / webapi)" do
  def ok_response(body = '{"ok":true}')
    double("response", body: body)
  end

  it "Slack Web API posts to chat.postMessage with Bearer token" do
    EventTrigger.configure do |c|
      c.enabled = true
      c.slack.enabled = true
      c.slack.token = "xoxb-123"
      c.slack.channel = "#alerts"
    end
    provider = EventTrigger::Providers::SlackProvider.new(
      config: EventTrigger.configuration.slack, global_config: EventTrigger.configuration
    )
    captured = nil
    allow(provider).to receive(:post_json) do |url, body, headers, service: "HTTP"|
      captured = { url: url, body: body, headers: headers }
      ok_response
    end
    expect(provider.deliver(EventTrigger::Event.new(name: "loan.activated", payload: { loan_id: 1 }))).to be true
    expect(captured[:url]).to eq("https://slack.com/api/chat.postMessage")
    expect(captured[:headers]["Authorization"]).to eq("Bearer xoxb-123")
    expect(captured[:body][:channel]).to eq("#alerts")
  end

  it "Slack Web API fails cleanly on ok:false" do
    EventTrigger.configure do |c|
      c.slack.enabled = true
      c.slack.token = "bad"
      c.slack.channel = "#x"
    end
    provider = EventTrigger::Providers::SlackProvider.new(
      config: EventTrigger.configuration.slack, global_config: EventTrigger.configuration
    )
    allow(provider).to receive(:post_json).and_return(ok_response('{"ok":false,"error":"invalid_auth"}'))
    expect { provider.deliver(EventTrigger::Event.new(name: "loan.activated", payload: {})) }
      .to raise_error(EventTrigger::Error, /invalid_auth/)
  end

  it "Telegram posts to sendMessage API and validates config" do
    EventTrigger.configure do |c|
      c.telegram.enabled = true
      c.telegram.bot_token = "BOT123"
      c.telegram.chat_id = "456"
    end
    provider = EventTrigger::Providers::TelegramProvider.new(
      config: EventTrigger.configuration.telegram, global_config: EventTrigger.configuration
    )
    captured = nil
    allow(provider).to receive(:post_json) do |url, body, *_a|
      captured = [url, body]
      ok_response
    end
    expect(provider.deliver(EventTrigger::Event.new(name: "loan.overdue", payload: { x: 1 }))).to be true
    expect(captured[0]).to eq("https://api.telegram.org/botBOT123/sendMessage")
    expect(captured[1][:chat_id]).to eq("456")

    missing = EventTrigger::Providers::TelegramProvider.new(
      config: EventTrigger::ProviderConfig.new(enabled: true),
      global_config: EventTrigger.configuration
    )
    expect { missing.deliver(EventTrigger::Event.new(name: "x", payload: {})) }
      .to raise_error(EventTrigger::Error, /bot_token/)
  end

  it "Teams posts to Graph API with Bearer token" do
    EventTrigger.configure do |c|
      c.teams.enabled = true
      c.teams.access_token = "TOK"
      c.teams.team_id = "T1"
      c.teams.channel_id = "C1"
    end
    provider = EventTrigger::Providers::TeamsProvider.new(
      config: EventTrigger.configuration.teams, global_config: EventTrigger.configuration
    )
    captured = nil
    allow(provider).to receive(:post_json) do |url, body, headers, service: "HTTP"|
      captured = { url: url, body: body, headers: headers }
      ok_response("{}")
    end
    expect(provider.deliver(EventTrigger::Event.new(name: "loan.activated", payload: { a: 1 }))).to be true
    expect(captured[:url]).to eq("https://graph.microsoft.com/v1.0/teams/T1/channels/C1/messages")
    expect(captured[:headers]["Authorization"]).to eq("Bearer TOK")
  end
end
