# frozen_string_literal: true

require_relative "lib/event_trigger/version"

Gem::Specification.new do |spec|
  spec.name = "event_trigger"
  spec.version = EventTrigger::VERSION
  spec.authors = ["Kamlesh Parmar"]
  spec.email = ["malviyak00@gmail.com"]

  spec.summary = "Configurable event-based notification system for Ruby and Rails."
  spec.description = "EventTrigger provides a simple event system with pluggable " \
                     "notification providers (Slack, Email, Webhook, custom). " \
                     "Configure providers once, then call EventTrigger.trigger(\"event.name\", data: {...}) " \
                     "and the gem dispatches to the enabled providers configured for that event. " \
                     "Works in plain Ruby and Ruby on Rails."
  spec.homepage = "https://github.com/mrmalvi/event_trigger"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      f == gemspec || f.end_with?(".gem") || f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "net-smtp", ">= 0.3"
end
