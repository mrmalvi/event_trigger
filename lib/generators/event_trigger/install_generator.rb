# frozen_string_literal: true

require "rails/generators"

module EventTrigger
  module Generators
    # Copies the default initializer into the host Rails app:
    #
    #   rails generate event_trigger:install
    #
    # Pass --force to overwrite an existing initializer. The Railtie also
    # auto-creates this file when missing, so in practice you rarely need
    # to run the generator by hand.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Copy EventTrigger initializer to config/initializers/event_trigger.rb"

      def copy_initializer
        copy_file "event_trigger.rb",
                  "config/initializers/event_trigger.rb"
      end
    end
  end
end
