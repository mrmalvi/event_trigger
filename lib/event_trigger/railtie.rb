# frozen_string_literal: true

# Explicit: FileUtils is used by the initializer bootstrap below.
# Must never raise at require time.
begin
  require "fileutils"
rescue LoadError
  nil
end

module EventTrigger
  # Rails integration:
  # 1. Applies safe defaults as soon as the gem is bundled (so the app
  #    works with zero configuration).
  # 2. Auto-creates config/initializers/event_trigger.rb in the host app
  #    when missing, so the user always has an editable copy of the
  #    default block (no manual `rails generate` step needed). Never
  #    overwrites an existing file.
  # 3. Hooks Rails.logger in automatically (unless the app already set one).
  #
  # Order: Railtie initializer runs BEFORE the host app's initializers, so
  # anything in config/initializers/event_trigger.rb wins over these defaults.
  #
  # Boot safety: every hook is wrapped so a failure here can never stop
  # the host application from booting.
  if defined?(Rails::Railtie)
    class Railtie < Rails::Railtie
      generators do
        require "generators/event_trigger/install_generator" if defined?(Rails::Generators)
      rescue StandardError
        nil
      end

      initializer "event_trigger.configure_rails_defaults", before: :load_environment_config do
        begin
          require "event_trigger" unless defined?(EventTrigger::Dispatcher)
          EventTrigger.apply_defaults!
          if defined?(Rails.logger) && Rails.logger && EventTrigger.configuration.logger.nil?
            EventTrigger.configuration.logger = Rails.logger
          end
        rescue StandardError => e
          # Never break app boot because of notification defaults.
          begin
            Rails.logger&.warn("[EventTrigger] defaults could not be applied: #{e.class}: #{e.message}")
          rescue StandardError
            nil
          end
        end
      end

      # Runs after app initializers are loaded: if the app has no
      # initializer of its own, write the default one so it exists on
      # disk for the user to edit. Skipped in test to keep suites hermetic.
      initializer "event_trigger.ensure_initializer_present", after: :load_environment do
        begin
          next unless defined?(Rails.root) && Rails.root
          next if defined?(Rails.env) && Rails.env.test?

          dest = Rails.root.join("config/initializers/event_trigger.rb")
          next if File.exist?(dest)

          src_candidates = [
            File.expand_path("../../generators/event_trigger/templates/event_trigger.rb", __dir__),
            File.expand_path("../../../generators/event_trigger/templates/event_trigger.rb", __FILE__)
          ]
          src = src_candidates.find { |p| File.exist?(p) }
          next unless src

          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest)
          Rails.logger&.info("[EventTrigger] created #{dest} with defaults (edit to customize)")
        rescue StandardError
          nil # never break boot because of the initializer copy
        end
      end
    end
  end
end
