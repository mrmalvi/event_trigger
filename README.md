# EventTrigger

Configurable event-based notification system for Ruby and Rails.

Configure notification providers **once**, then simply call:

```ruby
EventTrigger.trigger("loan.activated", data: { loan_id: 123, customer_name: "Kamlesh" })
```

The gem determines automatically which **enabled** providers are
configured for that event and executes only those providers.
Anything can be sent in `data:` -- passed through to providers/handlers.

## Features

- Providers: **Slack**, **Email**, **Webhook**, **Discord**, **WhatsApp (Twilio)**, plus custom providers
- Central `EventTrigger.configure` block (plain Ruby and Rails)
- Per-provider `enabled` flag + global `config.enabled` kill-switch
- Per-provider `events` allow-list (`nil`/empty = all events)
- Simple API: `trigger(name, data:)` + `on(name) { |event| }`
- Adapter architecture: every provider implements `#deliver(event)`
- Failure isolation: one provider failing never blocks others
- Optional logging: triggered / executed / skipped / failed
- No app-specific business logic -- just events + providers

## Installation

```ruby
gem "event_trigger"
```

```sh
bundle install
```

Requires Ruby >= 2.6. No runtime dependencies (stdlib only).

## Configuration

```ruby
EventTrigger.configure do |config|
  config.enabled = true
  config.logger = Logger.new($stdout) # optional; nil = silent

  config.slack.enabled = true
  config.slack.webhook_url = ENV["SLACK_WEBHOOK_URL"]
  config.slack.events = ["loan.activated", "loan.overdue", "payment.received"]

  config.email.enabled = false
  config.email.from = ENV["EVENT_TRIGGER_EMAIL_FROM"]
  config.email.to = "ops@example.com"
  config.email.events = ["loan.activated", "loan.foreclosed"]

  config.webhook.enabled = true
  config.webhook.url = ENV["EVENT_TRIGGER_WEBHOOK_URL"]
  config.webhook.events = ["loan.activated"]
end
```

Shortcuts `config.slack_webhook_url=` and `config.email_from=` delegate
to the per-provider configs.

`events` is an allow-list per provider. `nil` (default) or `[]` means
**ALL events** — the provider runs for every trigger (as long as it is
enabled):

```ruby
config.slack.events = nil  # or [] → all events
```

### Rails initializer

Generate the default config (recommended):

```sh
rails generate event_trigger:install
# overwrite an existing one:
rails generate event_trigger:install --force
```

This copies `config/initializers/event_trigger.rb` into your app:

```ruby
EventTrigger.configure do |config|
  config.enabled = true

  config.slack.enabled = true
  config.slack.webhook_url = ENV["SLACK_WEBHOOK_URL"]
  # NEW: Slack Web API mode (additive) — set BOTH to use chat.postMessage:
  # config.slack.token = ENV["SLACK_BOT_TOKEN"]
  # config.slack.channel = ENV["SLACK_CHANNEL"]
  config.slack.events = nil # or your event names

  config.email.enabled = false
  # Rails apps: uncomment for ActionMailer delivery:
  # config.email.delivery_method = :action_mailer
  config.email.from = ENV["EVENT_TRIGGER_EMAIL_FROM"]
  # NEW: spec-style SMTP hash also works (string/symbol keys):
  # config.email.smtp = {
  #   address: ENV["SMTP_ADDRESS"], port: ENV["SMTP_PORT"],
  #   username: ENV["SMTP_USERNAME"], password: ENV["SMTP_PASSWORD"]
  # }
  config.email.events = nil

  config.webhook.enabled = false
  # NEW: config.webhook[:method] = :post  # :post/:put/:patch/:delete/:get
  config.discord.enabled = false
  config.whatsapp.enabled = false
  # NEW providers (all disabled by default):
  # config.telegram.enabled = true
  # config.telegram.bot_token = ENV["TELEGRAM_BOT_TOKEN"]
  # config.telegram.chat_id = ENV["TELEGRAM_CHAT_ID"]
  # config.teams.enabled = true
  # config.teams.access_token = ENV["TEAMS_ACCESS_TOKEN"]
  # config.teams.team_id = ENV["TEAMS_TEAM_ID"]
  # config.teams.channel_id = ENV["TEAMS_CHANNEL_ID"]
  # config.sms.enabled = true  # provider :twilio (Twilio Messaging API)
  # config.sms.account_sid = ENV["TWILIO_ACCOUNT_SID"]
  # config.sms.auth_token = ENV["TWILIO_AUTH_TOKEN"]
  # config.sms.from = ENV["TWILIO_FROM"]
end
```

No generator run? The gem's Railtie auto-applies these defaults on
boot and auto-creates the initializer file when missing (never
overwrites). Manual alternative: copy `examples/initializer.rb` to
`config/initializers/event_trigger.rb`.

## Triggering events

```ruby
EventTrigger.trigger("loan.activated", data: { loan_id: 123, customer_name: "Kamlesh" })
```

Rules: `loan.activated` with Slack+Email enabled and subscribed runs both;
`loan.overdue` with only Slack subscribed runs Slack only; with
`config.enabled = false` nothing runs.

`trigger` still returns the `Event` (unchanged). NEW additive result:
the provider-wise map is exposed without changing the return value:

```ruby
event = EventTrigger.trigger("loan.activated", data: { loan_id: 123 })
EventTrigger.last_result
# => { event: "loan.activated", status: "success",
#      providers: { slack: "sent", email: "sent", discord: "skipped (disabled)",
#                   telegram: "skipped (disabled)", teams: "skipped (disabled)",
#                   sms: "skipped (disabled)", webhook: "sent" } }
event.last_result # same hash
```

Statuses: `"sent"` | `"failed"` | `"skipped ..."` (reason included).
One provider failing never stops the others (isolation preserved).

## Handlers

```ruby
EventTrigger.on("loan.activated") do |event|
  puts "Loan #{event.payload[:loan_id]} activated"
end
```

`event` exposes `#name`, `#payload`, `#timestamp`. Use `off(name)` to
remove handlers. Handler errors are logged, never raised.

## Providers

Slack posts `{ text: }` to `hooks.slack.com` URLs (error payloads render as
error plus backtrace lines) and a rich embed (`username: RailsErrorNotifier`,
Backtrace/Context fields) to other webhook URLs. Email sends via Net::SMTP
in plain Ruby (or ActionMailer when configured with `mailer`). Webhook POSTs
`{ event:, payload:, timestamp: }` as JSON.

Custom provider:

```ruby
class SmsProvider < EventTrigger::Provider
  def deliver(event)
    # use config + global_config
  end
end
EventTrigger.register_provider(:sms, SmsProvider)
EventTrigger.configure { |c| c.for(:sms).enabled = true }
```

Architecture: EventTrigger -> Event -> Enabled Providers
(Slack/Email/Webhook/Discord/WhatsApp).

## Discord provider (`config.discord`)

Ported from `RailsErrorNotifier`: posts the rich embed payload
(`username: RailsErrorNotifier`, Backtrace/Context fields, ~1014-char
truncation) to a Discord incoming-webhook URL.

```ruby
config.discord.enabled = true
config.discord.webhook_url = ENV["DISCORD_WEBHOOK_URL"]
config.discord.events = ["app.error"]
```

## WhatsApp provider (`config.whatsapp`, via Twilio)

Ported from `RailsErrorNotifier`:

```ruby
config.whatsapp.enabled = true
config.whatsapp.twilio_sid = ENV["TWILIO_ACCOUNT_SID"]
config.whatsapp.twilio_token = ENV["TWILIO_AUTH_TOKEN"]
config.whatsapp.twilio_from = ENV["TWILIO_WHATSAPP_FROM"] # whatsapp:+14155238886
config.whatsapp.twilio_to = ENV["TWILIO_WHATSAPP_TO"]
config.whatsapp.events = ["app.error"]
```

Per-trigger override: `data: { whatsapp_to: "whatsapp:+919..." }`.
Numbers without the `whatsapp:` scheme are normalized automatically.

## Logging

Set `config.logger`. Logs: event triggered, provider executed, provider
skipped (disabled / not subscribed), provider failed, handler failed.

## Public API

`configure`, `configuration`, `reset!`, `trigger(name, data:)`, `on`, `off`,
`register_provider`, `Provider#deliver`, `Registry`, `Dispatcher`.

## Development

```sh
bundle install
bundle exec rspec
```

See `examples/plain_ruby.rb` for a runnable demo.

## License

MIT -- see LICENSE.txt.

