# Debian Security Tracker JSON (security-tracker.debian.org/tracker/data/json):
#
#   { "openssl": { "CVE-2024-5535": { "description": "…",
#       "releases": { "bookworm": { "status": "resolved", "fixed_version": "3.0.14-1~deb12u1", "urgency": "not yet assigned" } } } } }
#
# Read member by member (JsonObjectStream). Kept: CVEs (not TEMP-…) of the
# releases asked for; skipped: "not affected" (fixed in version 0), and the
# issues Debian rates "unimportant" or leaves unsupported ("end-of-life").
# Debian rates few issues (most are "not yet assigned"); one it does not plan
# an advisory for ("nodsa": "Minor issue") is rated low.
#
# An open issue Debian will not fix through a security advisory keeps why as
# `distro_status` ("nodsa_reason"): "no_dsa" (minor, maybe in a point
# release), "postponed" (in a later update), "ignored" (not in this release).
module Vulnerabilities::DebianTracker
  URL = ENV.fetch("ELIO_DEBIAN_TRACKER_URL", "https://security-tracker.debian.org/tracker/data/json")
  def self.url(_release) = URL

  URGENCIES = { "low" => "low", "medium" => "medium", "high" => "high", "not yet assigned" => "unknown" }.freeze
  NODSA_REASONS = { "postponed" => "postponed", "ignored" => "ignored" }.freeze

  # Yields { release:, package:, cve:, fixed_version:, severity:, distro_status:, description: }.
  def self.each_row(io, releases:)
    releases = releases.to_set
    Vulnerabilities::JsonObjectStream.each(io) do |package, issues|
      raise Vulnerabilities::Error, I18n.t("vulnerabilities.debian_tracker.not_tracker") unless issues.is_a?(Hash)

      issues.each do |cve, issue|
        next unless cve.start_with?("CVE-") && issue.is_a?(Hash)

        issue.fetch("releases", {}).each do |release, state|
          next unless releases.include?(release)

          row = row(package, cve, issue, release, state)
          yield row if row
        end
      end
    end
  rescue Vulnerabilities::JsonObjectStream::Error, JSON::ParserError => e
    raise Vulnerabilities::Error, I18n.t("vulnerabilities.debian_tracker.unreadable", truncate: (e.message.truncate(120)))
  end

  def self.row(package, cve, issue, release, state)
    urgency = state["urgency"].to_s.delete("*").strip
    severity = URGENCIES[urgency]
    return unless severity

    severity = "low" if severity == "unknown" && state["nodsa"].present?
    fixed = state["status"] == "resolved" ? state["fixed_version"].presence : nil
    return if fixed == "0"

    { release: release, package: package, cve: cve, fixed_version: fixed, severity: severity, distro_status: (distro_status(state) unless fixed),
      description: issue["description"].to_s.squish.truncate(240).presence, primary: true }
  end

  def self.distro_status(state)
    return unless state.key?("nodsa")

    NODSA_REASONS.fetch(state["nodsa_reason"].to_s, "no_dsa")
  end
end
