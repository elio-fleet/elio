# The references of a CVE worth showing on its page, picked out of the
# lists the score providers already send (NVD, CVE.org): the Debian and
# Ubuntu advisories (DSA, DLA, USN) and the fixes (commits, patches).
# Stored in CveScore#data["references"] as [{ "url", "kind" }], at most
# LIMIT; nothing is fetched for them.
module Vulnerabilities::References
  KINDS = %w[advisory fix].freeze
  LIMIT = 20
  ADVISORY = %r{\A(?:www\.)?debian\.org/security/\d{4}/d[sl]a-|\Alists\.debian\.org/debian-(?:lts|security)-announce/|\A(?:www\.)?ubuntu\.com/security/notices/usn-}i
  FIX = %r{/commits?/[0-9a-f]{7,}|/-/commit/|/pull/\d+|/merge_requests/\d+|[?;&]h=[0-9a-f]{7,}|[?;&]id=[0-9a-f]{7,}|\.patch\z|\.diff\z}i

  # [{ "url", "kind" }] from [{ "url", "tags" }] (both providers use this shape).
  def self.pick(entries)
    Array(entries).filter_map do |entry|
      url = entry["url"].to_s.strip if entry.is_a?(Hash)
      next unless url&.match?(%r{\Ahttps?://[^\s]+\z}i) && url.length <= 500

      kind = kind_of(url, Array(entry["tags"]))
      { "url" => url, "kind" => kind } if kind
    end.uniq { |reference| reference["url"] }.sort_by { |reference| KINDS.index(reference["kind"]) }.first(LIMIT)
  end

  def self.kind_of(url, tags)
    path = url.sub(%r{\Ahttps?://}i, "")
    if path.match?(ADVISORY) then "advisory"
    elsif path.match?(FIX) || tags.any? { |tag| tag.to_s.casecmp?("patch") } then "fix"
    end
  end

  # A short name for a link: DSA-5724-1, USN-6859-1, else the host and the end of the path.
  def self.label(url)
    path = url.sub(%r{\Ahttps?://}i, "").sub(/[?#].*\z/, "")
    if (id = path[%r{/(d[sl]a-\d+(?:-\d+)?)}i, 1] || path[%r{/(usn-\d+-\d+)}i, 1]) then id.upcase
    elsif path.match?(%r{\Alists\.debian\.org/debian-lts-announce/}i) then "Debian LTS (#{path.split("/")[2..3].join("-")})"
    elsif path.match?(%r{\Alists\.debian\.org/debian-security-announce/}i) then "Debian security (#{path.split("/")[2..3].join("-")})"
    else
      host, *rest = path.split("/")
      [ host.delete_prefix("www."), rest.last(2).join("/").truncate(40) ].compact_blank.join(" · ")
    end
  end

  # The references of a CVE, from its stored scores, advisories first, without duplicates.
  def self.of(scores)
    scores.flat_map { |score| Array(score.data["references"]) }.uniq { |reference| reference["url"] }
          .select { |reference| KINDS.include?(reference["kind"]) }.sort_by { |reference| KINDS.index(reference["kind"]) }
  end
end
