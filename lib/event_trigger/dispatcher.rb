# frozen_string_literal: true

module EventTrigger
  # Fans an Event out to every enabled provider subscribed to that event,
  # then runs any user-registered handlers (EventTrigger.on).
  #
  # Guarantees:
  # - Global disable (config.enabled == false) => nothing runs.
  # - Only enabled providers subscribed to the event run.
  # - Unknown provider names are skipped (with a log line) instead of crashing.
  # - One provider raising never prevents the others from running;
  #   failures are logged and swallowed so all providers always run.
  # - Handler blocks are likewise isolated: a failing handler is logged
  #   and the rest still run.
  class Dispatcher
    def initialize(configuration)
      @configuration = configuration
    end

    # Returns the list of provider instances that were executed.
    def dispatch(event, handlers = [])
      log("event triggered: #{event.name} payload=#{event.payload.inspect}")
      return [] unless @configuration.enabled?

      executed = []
      providers_for(event.name).each do |name, provider_config|
        klass = Registry.fetch(name)
        if klass.nil?
          log("provider ':#{name}' has no registered class; skipping")
          next
        end
        unless provider_config.enabled
          log("provider ':#{name}' skipped (disabled)")
          next
        end
        unless provider_config.subscribed_to?(event.name)
          log("provider ':#{name}' skipped (not subscribed to '#{event.name}')")
          next
        end
        begin
          klass.new(config: provider_config, global_config: @configuration).deliver(event)
          log("provider ':#{name}' executed for '#{event.name}'")
          executed << name
        rescue StandardError => e
          log("provider ':#{name}' failed for '#{event.name}': #{e.class}: #{e.message}")
        end
      end

      Array(handlers).each do |handler|
        begin
          handler.call(event)
        rescue StandardError => e
          log("handler for '#{event.name}' failed: #{e.class}: #{e.message}")
        end
      end

      executed
    end

    private

    def providers_for(_event_name)
      @configuration.providers
    end

    def log(message)
      @configuration.logger&.info("[EventTrigger] #{message}")
    end
  end
end
