# frozen_string_literal: true

module EventTrigger
  # Value object representing a single triggered event.
  # Carries the event +name+ ("loan.activated"), an arbitrary +payload+ hash
  # (anything the caller passes via data:), and a timestamp.
  class Event
    attr_reader :name, :payload, :timestamp
    # Provider-wise result hash for this event's dispatch
    # ({ event:, status:, providers: }). Set by EventTrigger.trigger.
    attr_accessor :last_result

    def initialize(name:, payload: {})
      @name = name.to_s
      @payload = symbolize(payload || {})
      @timestamp = Time.now
      @last_result = nil
    end

    # Safe lookup: works with symbols, strings and non-symbolizable keys.
    def [](key)
      sym = begin
        key.to_sym
      rescue StandardError
        nil
      end
      return payload[sym] if sym && payload.key?(sym)

      payload[key.to_s]
    end

    def to_h
      { name: name, payload: payload, timestamp: timestamp }
    end

    private

    # Defensive: non-Hash payloads become {}, and odd keys (Integer,
    # objects without #to_sym) fall back to strings instead of raising.
    # This guarantees Event.new can never crash the caller.
    def symbolize(hash)
      return {} unless hash.is_a?(Hash)

      hash.each_with_object({}) do |(k, v), memo|
        key = begin
          k.respond_to?(:to_sym) ? k.to_sym : k.to_s
        rescue StandardError
          k.to_s
        end
        memo[key] = v
      end
    rescue StandardError
      {}
    end
  end
end
