module DnsHelper
  SOURCE_CLASSES = { "ovh" => "bg-sky-100 text-sky-800 dark:bg-sky-950 dark:text-sky-200", "technitium" => "bg-violet-100 text-violet-800 dark:bg-violet-950 dark:text-violet-200" }.freeze

  # Badge of the extension a DNS record comes from.
  def dns_source_badge(source)
    tag.span(DnsRecord.source_label(source), class: "dns-source badge #{SOURCE_CLASSES.fetch(source.to_s, "bg-subtle text-ink-2")}", data: { source: source })
  end
end
