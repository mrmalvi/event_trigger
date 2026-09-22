# frozen_string_literal: true

require_relative "../provider"
require_relative "http_poster"

module EventTrigger
  module Providers
    # Sends event notifications to a Microsoft Teams channel via the
    # Microsoft Graph API.
    #
    #   API: POST https://graph.microsoft.com/v1.0/teams/{team-id}/channels/{channel-id}/messages
    #   Auth: Authorization: Bearer <ACCESS_TOKEN>
    #
    # Config:
    #   config.teams.enabled = true
    #   config.teams.access_token = ENV["TEAMS_ACCESS_TOKEN"]
    #   config.teams.team_id = ENV["TEAMS_TEAM_ID"]
    #   config.teams.channel_id = ENV["TEAMS_CHANNEL_ID"]
    #   config.teams.events = ["loan.activated"]
    #
    # Crash-safe: failures raise EventTrigger::Error (Dispatcher logs them).
    class TeamsProvider < Provider
      include HttpPoster

      GRAPH_BASE = "https://graph.microsoft.com/v1.0"

      def self.provider_name
        :teams
      end

      def deliver(event)
        token = config.access_token
        team_id = config.team_id
        channel_id = config.channel_id
        raise Error, "Teams access_token is not configured" if blank?(token)
        raise Error, "Teams team_id is not configured" if blank?(team_id)
        raise Error, "Teams channel_id is not configured" if blank?(channel_id)

        url = "#{GRAPH_BASE}/teams/#{team_id}/channels/#{channel_id}/messages"
        post_json(
          url, { body: { contentType: "text", content: message_text(event) } },
          { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" },
          service: "Teams"
        )
        log("delivered event '#{event.name}'")
        true
      end


      private

      def message_text(event)
        payload = event.payload
        err = payload[:error] || payload["error"]
        return err.to_s if err

        summary = payload.map { |k, v| "#{k}: #{v}" }.join(", ")
        summary = payload.inspect if summary.empty?
        "[#{event.name}] #{summary}"
      end

      def blank?(value)
        value.nil? || value.to_s.strip.empty?
      end
    end
  end
end
