# frozen_string_literal: true

require_relative "../provider"

module EventTrigger
  module Providers
    # Sends event notifications via email.
    #
    # Works in two modes:
    # 1. Rails mode -- if ActionMailer is loaded and
    #    config.email.mailer is set (a mailer class) or
    #    config.email.delivery_method == :action_mailer, the event is
    #    delivered through ActionMailer.
    # 2. Plain-Ruby mode -- otherwise delivered via stdlib Net::SMTP using
    #    config.email.smtp_settings (+ from/to addresses).
    #
    # Config:
    #   config.email.enabled = true
    #   config.email.from = "no-reply@example.com"
    #   config.email.to = "ops@example.com"            # default recipient
    #   config.email.subject_prefix = "[EventTrigger]" # optional
    #   config.email.events = ["loan.activated"]
    #
    # Per-trigger overrides: EventTrigger.trigger("x", data: { email_to:, email_subject:, ... })
    class EmailProvider < Provider
      def self.provider_name
        :email
      end

      def deliver(event)
        from = config.from || global_config.email_from
        to = event.payload[:email_to] || event.payload["email_to"] || config.to
        raise Error, "Email `from` is not configured" if from.nil? || from.to_s.strip.empty?
        raise Error, "Email `to` is not configured" if to.nil? || to.to_s.strip.empty?

        subject = event.payload[:email_subject] || event.payload["email_subject"] ||
                  build_subject(event)
        body = build_body(event)

        if action_mailer_delivery?
          deliver_via_action_mailer(from, to, subject, body, event)
        else
          deliver_via_smtp(from, to, subject, body)
        end
        log("delivered event '#{event.name}' to #{Array(to).join(', ')}")
        true
      end

      private

      def action_mailer_delivery?
        defined?(ActionMailer::Base) && (config.mailer || config.delivery_method == :action_mailer)
      end

      def deliver_via_action_mailer(from, to, subject, body, _event)
        mailer = config.mailer
        if mailer
          mailer.event_notification(from, to, subject, body).deliver_now
        else
          Class.new(ActionMailer::Base) do
            def event_notification(from, to, subject, body)
              mail(from: from, to: to, subject: subject, body: body)
            end
          end.event_notification(from, to, subject, body).deliver_now
        end
      end

      def deliver_via_smtp(from, to, subject, body)
        require "net/smtp"
        settings = smtp_settings
        message = <<~MSG
          From: #{from}
          To: #{Array(to).join(", ")}
          Subject: #{subject}
          MIME-Version: 1.0
          Content-Type: text/plain; charset=UTF-8

          #{body}
        MSG
        Net::SMTP.start(
          settings[:address] || "localhost",
          settings[:port] || 25,
          settings[:domain] || "localhost",
          settings[:user_name],
          settings[:password],
          settings[:authentication] || :plain
        ) do |smtp|
          smtp.send_message(message, from, Array(to))
        end
      end

      def smtp_settings
        config.smtp_settings || {}
      end

      def build_subject(event)
        prefix = config.subject_prefix || "[EventTrigger]"
        custom = event.payload[:subject] || event.payload["subject"]
        return custom.to_s if custom

        "#{prefix} #{event.name}"
      end

      def build_body(event)
        lines = ["Event: #{event.name}", "Time: #{event.timestamp}", ""]
        event.payload.each do |k, v|
          next if [:email_to, :email_subject, "email_to", "email_subject"].include?(k)

          lines << "#{k}: #{v}"
        end
        lines.join("\n")
      end
    end
  end
end
