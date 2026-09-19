# frozen_string_literal: true

module EventTrigger
  # Value object representing a single triggered event.
  # Carries the event +name+ ("loan.activated"), an arbitrary +payload+ hash
  # (anything the caller passes via data:), and a timestamp.
  class Event
    attr_reader :name, :payload, :timestamp

    def initialize(name:, payload: {})
      @name = name.to_s
      @payload = symbolize(payload || {})
      @timestamp = Time.now
    end

    def [](key)
      payload[key.to_sym] || payload[key.to_s]
    end

    def to_h
      { name: name, payload: payload, timestamp: timestamp }
    end

    private

    def symbolize(hash)
      return {} unless hash.is_a?(Hash)

      hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
      end
    end
  end
end
