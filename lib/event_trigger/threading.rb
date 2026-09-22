# frozen_string_literal: true

require "monitor"

module EventTrigger
  # Reentrant lock shared by the provider registry, configuration and
  # handler store (Monitor, not Mutex, so a callback may re-enter).
  #
  # Defined in its own file so it is available BEFORE registry.rb runs its
  # load-time registration (otherwise built-in providers would silently
  # fail to register at require time).
  def self.lock
    @lock ||= Monitor.new
  rescue StandardError
    # Extremely defensive: never let locking break loading.
    Monitor.new
  end
end
