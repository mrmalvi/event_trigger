# frozen_string_literal: true

require "timeout"

module EventTrigger
  # Fans an Event out to every enabled provider subscribed to that event,
  # then runs any user-registered handlers (EventTrigger.on).
  #
  # Safety contract (never harms the host app or system):
  # - Global disable (config.enabled == false) => nothing runs.
  # - Only enabled providers subscribed to the event run.
  # - Unknown provider names are skipped (with a log line) instead of crashing.
  # - One provider raising never prevents the others from running;
  #   failures are logged and swallowed so all providers always run.
  # - Every provider call is wrapped in a hard timeout
  #   (config.delivery_timeout, default 15s; per-provider override via
  #   config.<provider>.delivery_timeout) so a hanging API can never block
  #   a web request forever. 0 disables the timeout.
  # - Handler blocks are isolated: a failing handler is logged and the rest
  #   still run. Optional handler timeout via config.handler_timeout (0 = off).
  # - Logging failures (closed IO, disk full, broken custom logger) are
  #   swallowed — a logger must never break dispatch.
  # - #dispatch itself never raises: any internal error is captured.
  #
  # Result shape (additive):
  #   { event:, status:, providers: { slack: "sent", email: "failed", ... } }
  # statuses: "sent" | "failed" | "skipped ..." (reason included).
  class Dispatcher
    SKIP_DISABLED = "skipped (disabled)"
    SKIP_UNSUBSCRIBED_PREFIX = "skipped (not subscribed"
    SKIP_UNREGISTERED = "skipped (unregistered)"
    STATUS_SENT = "sent"
    STATUS_FAILED = "failed"
    STATUS_ERROR = "error"
    UNKNOWN = "<unknown>"
    SECRET_KEYS = %w[token secret password passwd api_key apikey auth authorization bearer webhook sid].freeze

    def initialize(configuration)
      @configuration = configuration
    end

    # Returns the provider-wise result hash. Still runs handlers.
    # Never raises.
    def dispatch(event, handlers = [])
      log("event triggered: #{event_name(event)} payload=#{redact_payload(payload_of(event))}")
      return build_result(event, {}, disabled_globally: true) unless globally_enabled?

      statuses = {}
      providers_snapshot.each { |name, cfg| statuses[name] = run_provider(name, cfg, event) }
      run_handlers(handlers, event)
      build_result(event, statuses)
    rescue StandardError => e
      # Absolute last line of defence: a bug inside the dispatcher itself
      # must never surface in the host app.
      log("dispatcher error for '#{event_name(event)}': #{e.class}: #{redact(e.message)}")
      build_result(event, {}, internal_error: "#{e.class}: #{redact(e.message)}")
    end

    private

    # Snapshot so concurrent configuration changes can't break iteration.
    def providers_snapshot
      @configuration.providers.to_a
    rescue StandardError
      []
    end

    def globally_enabled?
      @configuration.enabled?
    rescue StandardError
      true
    end

    def run_provider(name, provider_config, event)
      klass = Registry.fetch(name)
      if klass.nil?
        log("provider ':#{name}' has no registered class; skipping")
        return SKIP_UNREGISTERED
      end
      unless provider_config.enabled
        log("provider ':#{name}' skipped (disabled)")
        return SKIP_DISABLED
      end
      unless provider_config.subscribed_to?(event_name(event))
        log("provider ':#{name}' skipped (not subscribed to '#{event_name(event)}')")
        return "#{SKIP_UNSUBSCRIBED_PREFIX} to '#{event_name(event)}')"
      end

      deliver_with_timeout(klass, name, provider_config, event)
      log("provider ':#{name}' executed for '#{event_name(event)}'")
      STATUS_SENT
    rescue StandardError => e
      log("provider ':#{name}' failed for '#{event_name(event)}': #{e.class}: #{redact(e.message)}")
      STATUS_FAILED
    end

    # Hard timeout guard around the provider call (covers slow DNS, hung
    # sockets, Twilio/SMTP stalls...). Timeout::Error is a StandardError,
    # so it is reported as "failed" and the loop continues.
    def deliver_with_timeout(klass, name, provider_config, event)
      timeout = timeout_for(provider_config)
      instance = klass.new(config: provider_config, global_config: @configuration)
      return instance.deliver(event) if timeout.nil? || timeout <= 0

      Timeout.timeout(timeout, Error, "provider ':#{name}' timed out after #{timeout}s") do
        instance.deliver(event)
      end
    end

    def timeout_for(provider_config)
      @configuration.timeout_for(provider_config)
    rescue StandardError
      Configuration::DEFAULT_DELIVERY_TIMEOUT
    end

    def run_handlers(handlers, event)
      Array(handlers).each { |handler| run_handler(handler, event) }
    rescue StandardError => e
      log("handler iteration failed: #{e.class}: #{redact(e.message)}")
    end

    def run_handler(handler, event)
      return unless handler.respond_to?(:call)

      timeout = handler_timeout
      if timeout.nil? || timeout <= 0
        handler.call(event)
      else
        Timeout.timeout(timeout, Error, "handler for '#{event_name(event)}' timed out after #{timeout}s") do
          handler.call(event)
        end
      end
    rescue StandardError => e
      log("handler for '#{event_name(event)}' failed: #{e.class}: #{redact(e.message)}")
    end

    def handler_timeout
      value = @configuration.handler_timeout
      value.nil? ? 0 : value.to_f
    rescue StandardError
      0
    end

    def build_result(event, statuses, disabled_globally: false, internal_error: nil)
      if disabled_globally
        statuses = providers_snapshot.map { |k, _| [k, SKIP_DISABLED] }.to_h
      end
      # Overall status mirrors the documented API shape:
      # "success" unless the dispatcher itself blew up.
      result = { event: event_name(event), status: "success", providers: statuses }
      return result unless internal_error

      result.merge(status: STATUS_ERROR, error: internal_error)
    end

    # Safe accessor: an Event-like object whose #name raises must not
    # break the dispatcher.
    def event_name(event)
      event.respond_to?(:name) ? event.name.to_s : UNKNOWN
    rescue StandardError
      UNKNOWN
    end

    def payload_of(event)
      event.payload
    rescue StandardError
      {}
    end

    # Logging must never break dispatch (closed IO, disk full, broken
    # custom logger, ...).
    def log(message)
      logger = @configuration.logger
      return unless logger.respond_to?(:info)

      logger.info("[EventTrigger] #{message}")
    rescue StandardError
      nil
    end

    # Never log credential-looking fragments (tokens, passwords, ...).
    def redact(message)
      str = message.to_s.dup
      SECRET_KEYS.each do |key|
        str.gsub!(/#{key}[^,\s\]}]*[\w\-\.\/~+=\/]+/i, "#{key}=[FILTERED]")
      end
      str
    rescue StandardError
      "[unprintable]"
    end

    # Payload logging is capped: a huge payload must not bloat logs/memory.
    def redact_payload(payload, limit = 2000)
      return "{}" unless payload.is_a?(Hash)

      redacted = payload.each_with_object({}) { |(k, v), memo| memo[k] = secret_key?(k) ? "[FILTERED]" : v }
      text = redacted.inspect
      text.length > limit ? "#{text[0, limit]}…(truncated)" : text
    rescue StandardError
      "{}"
    end

    def secret_key?(key)
      k = key.to_s.downcase
      SECRET_KEYS.any? { |s| k.include?(s) }
    rescue StandardError
      false
    end
  end
end
