# frozen_string_literal: true

require "spec_helper"

# Safety guarantees: the gem must NEVER crash, hang or harm the host app
# or the system, no matter what providers, payloads or loggers do.
RSpec.describe "EventTrigger safety guarantees" do
  def disable_extras(c)
    c.webhook.enabled = false
    c.discord.enabled = false
    c.whatsapp.enabled = false
    c.telegram.enabled = false
    c.teams.enabled = false
    c.sms.enabled = false
  end

  it "times out a hanging provider instead of blocking the app, then continues" do
    slow = double("slow")
    allow(slow).to receive(:deliver) { sleep 5 }
    allow(EventTrigger::Providers::SlackProvider).to receive(:new).and_return(slow)

    fast = double("fast")
    allow(fast).to receive(:deliver).and_return(true)
    allow(EventTrigger::Providers::EmailProvider).to receive(:new).and_return(fast)

    EventTrigger.configure do |c|
      c.enabled = true
      c.delivery_timeout = 0.3
      c.slack.enabled = true
      c.email.enabled = true
      disable_extras(c)
    end

    started = Time.now
    expect { EventTrigger.trigger("loan.activated", data: { loan_id: 1 }) }.not_to raise_error
    expect(Time.now - started).to be < 3
    expect(EventTrigger.last_result[:providers][:slack]).to eq("failed")
    expect(fast).to have_received(:deliver)
  end

  it "supports a per-provider timeout override" do
    slow = double("slow")
    allow(slow).to receive(:deliver) { sleep 5 }
    allow(EventTrigger::Providers::SlackProvider).to receive(:new).and_return(slow)

    EventTrigger.configure do |c|
      c.enabled = true
      c.delivery_timeout = 30 # global is generous...
      c.slack.delivery_timeout = 0.2 # ...but slack gets 0.2s
      c.slack.enabled = true
      disable_extras(c)
    end

    started = Time.now
    EventTrigger.trigger("loan.activated", data: {})
    expect(Time.now - started).to be < 3
    expect(EventTrigger.last_result[:providers][:slack]).to eq("failed")
  end

  it "survives a provider whose constructor raises" do
    allow(EventTrigger::Providers::SlackProvider).to receive(:new).and_raise(ArgumentError, "bad init")
    EventTrigger.configure { |c| c.enabled = true; c.slack.enabled = true }
    expect { EventTrigger.trigger("x", data: {}) }.not_to raise_error
    expect(EventTrigger.last_result[:providers][:slack]).to eq("failed")
  end

  it "survives a logger that raises (disk full / closed IO / broken logger)" do
    exploding = Object.new
    def exploding.info(*)
      raise IOError, "log write failed"
    end
    EventTrigger.configure do |c|
      c.enabled = true
      c.logger = exploding
      c.slack.enabled = true
    end
    allow_any_instance_of(EventTrigger::Providers::SlackProvider).to receive(:deliver).and_return(true)
    expect { EventTrigger.trigger("x", data: {}) }.not_to raise_error
    expect(EventTrigger.last_result[:providers][:slack]).to eq("sent")
  end

  it "survives weird payloads (non-hash data, un-symbolizable keys, nil)" do
    EventTrigger.configure { |c| c.enabled = true }
    expect { EventTrigger.trigger("x", data: nil) }.not_to raise_error
    expect { EventTrigger.trigger("x", data: "not a hash") }.not_to raise_error
    expect { EventTrigger.trigger("x", data: { 1 => "int key", :ok => 1 }) }.not_to raise_error
    expect { EventTrigger.trigger(nil, data: {}) }.not_to raise_error
    expect(EventTrigger.last_result).to be_a(Hash)
  end

  it "survives an event-like object that raises on #name" do
    bogus = Object.new
    dispatcher = EventTrigger::Dispatcher.new(EventTrigger.configuration)
    expect { dispatcher.dispatch(bogus) }.not_to raise_error
    expect(dispatcher.dispatch(bogus)[:event]).to eq("<unknown>")
  end

  it "optionally enforces a handler timeout (off by default)" do
    EventTrigger.configure do |c|
      c.enabled = true
      c.handler_timeout = 0.3
    end
    ran = []
    EventTrigger.on("x") { sleep 5 }
    EventTrigger.on("x") { ran << :second }

    started = Time.now
    expect { EventTrigger.trigger("x", data: {}) }.not_to raise_error
    expect(Time.now - started).to be < 3
    expect(ran).to eq([:second])
  end

  it "isolates handlers that raise (default: no handler timeout)" do
    EventTrigger.configure { |c| c.enabled = true }
    ran = []
    EventTrigger.on("x") { raise "handler boom" }
    EventTrigger.on("x") { ran << :second }
    expect { EventTrigger.trigger("x", data: {}) }.not_to raise_error
    expect(ran).to eq([:second])
  end

  it "applies open/read timeouts to SMTP so a dead server cannot hang the app" do
    config = EventTrigger::ProviderConfig.new(enabled: true)
    config.from = "a@x.com"
    config.to = "b@x.com"
    provider = EventTrigger::Providers::EmailProvider.new(
      config: config, global_config: EventTrigger.configuration
    )

    smtp = double("smtp")
    allow(smtp).to receive(:respond_to?).and_return(true)
    allow(smtp).to receive(:open_timeout=)
    allow(smtp).to receive(:read_timeout=)
    allow(smtp).to receive(:write_timeout=)
    allow(smtp).to receive(:start).and_yield
    allow(smtp).to receive(:send_message)
    allow(Net::SMTP).to receive(:new).and_return(smtp)

    provider.deliver(EventTrigger::Event.new(name: "x", payload: {}))
    expect(smtp).to have_received(:open_timeout=).with(5)
    expect(smtp).to have_received(:read_timeout=).with(10)
  end

  it "never raises from trigger even if the dispatcher itself blows up" do
    allow(EventTrigger::Dispatcher).to receive(:new).and_raise(NoMethodError, "internal bug")
    EventTrigger.configure { |c| c.enabled = true }
    expect { EventTrigger.trigger("x", data: {}) }.not_to raise_error
    expect(EventTrigger.last_result[:status]).to eq("error")
  end

  it "loads provider-specific gems lazily (no eager require at load time)" do
    %w[whatsapp_provider sms_provider email_provider].each do |file|
      src = File.read(File.expand_path("../lib/event_trigger/providers/#{file}.rb", __dir__))
      expect(src).not_to match(/^require "twilio-ruby"/), "#{file} must not require twilio-ruby at load time"
      expect(src).not_to match(/^require "net\/smtp"/), "#{file} must not require net/smtp at load time"
    end
    http_src = File.read(File.expand_path("../lib/event_trigger/providers/http_poster.rb", __dir__))
    expect(http_src).not_to match(/^require "faraday"/)
  end

  it "keeps Ruby's Object#send working on provider instances" do
    provider = EventTrigger::Providers::WebhookProvider.new(
      config: EventTrigger::ProviderConfig.new(enabled: true), global_config: EventTrigger.configuration
    )
    # internal Ruby send must not be treated as a notification
    expect(provider.send(:provider_name)).to eq(:webhook)
    expect(provider.send(:respond_to?, :deliver)).to be true

    provider.config.url = "https://example.com/hook"
    allow(provider).to receive(:request_json) { |*_a| double(code: "200") }
    expect(provider.send("loan.activated", { loan_id: 1 })).to be true
    expect(provider.send("loan.activated")).to be true
  end

  it "registers every built-in provider at require time (fresh process)" do
    script = <<~RUBY
      require "event_trigger"
      puts EventTrigger::Registry.all.keys.sort.inspect
      puts EventTrigger.last_result.inspect
      # a real trigger with zero config must not raise and must dispatch nothing
      EventTrigger.trigger("boot.check", data: { a: 1 })
      puts EventTrigger.last_result[:providers].keys.sort.inspect
    RUBY
    out = IO.popen(["bundle", "exec", "ruby", "-Ilib", "-e", script], chdir: File.expand_path("..", __dir__), &:read)
    expect(out).to include("[:discord, :email, :slack, :sms, :teams, :telegram, :webhook, :whatsapp]")
  end

  it "is safe under concurrent triggers" do
    EventTrigger.configure { |c| c.enabled = true }
    allow_any_instance_of(EventTrigger::Providers::SlackProvider).to receive(:deliver).and_return(true)

    errors = []
    threads = Array.new(8) do
      Thread.new do
        20.times { |i| EventTrigger.trigger("concurrent.event", data: { i: i }) }
      rescue StandardError => e
        errors << e
      end
    end
    threads.each(&:join)
    expect(errors).to be_empty
  end
end
