# Display of the OVHcloud resources (OvhResource).
module OvhHelper
  FIREWALL_VERDICTS = { permit: :warn, deny: :good, restricted: :good, not_covered: :warn }.freeze # labels: ovh_helper.verdicts.*

  def ovh_expiration(resource)
    return tag.span("—", class: "text-ink-3") unless resource.expires_at

    days = resource.days_left
    text = "#{l(resource.expires_at, format: :long)}#{" #{t("ovh_helper.auto_renew")}" if resource.data["renew_automatic"]}"
    css = if days <= 7 then "text-crit-ink font-medium" elsif days <= 30 && !resource.data["renew_automatic"] then "text-warn-ink" else "text-ink-2" end
    tag.span(text, class: "ovh-expiration #{css}", title: t("ovh_helper.in_days", count: days))
  end

  def ovh_firewall_rule(rule)
    [ rule["sequence"], t(rule["action"] == "permit" ? "ovh_helper.permit" : "ovh_helper.deny"), rule["protocol"], rule["destinationPort"], (rule["source"] && t("ovh_helper.from_source", source: (rule["source"]))) ].compact_blank.join(" ")
  end

  def ovh_firewall_badge(verdict)
    return tag.span(t("ovh_helper.no_firewall"), class: "text-xs text-ink-3") unless verdict

    status_badge(FIREWALL_VERDICTS.fetch(verdict), t("ovh_helper.verdicts.#{verdict}"), class: "ovh-firewall-verdict")
  end

  def ovh_match_label(resource) = resource.matched_by.presence && t("ovh_resource.matches.#{resource.matched_by}", default: "")
end
