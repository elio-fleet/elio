# Newer versions of a pinned image tag among the tags of its repository
# (ImageRegistry::Client#tags): "7.0.11" → the last fix of its series
# ("7.0.15") and the last version of its major ("7.4.6"). Only tags of the
# same shape count: as many numbers, the same variant ("3.11.4-slim-bookworm"
# only compares with "3.11.x-slim-bookworm"); pre-releases are ignored.
#
#   ImageRegistry::Versions.newer("7.0.11", tags) # => { patch: "7.0.15", major: "7.4.6" }
module ImageRegistry::Versions
  TAG = /\Av?(\d+(?:\.\d+){1,3})(-[a-z0-9][a-z0-9.-]*)?\z/i
  PRE_RELEASE = /(?:\A|[-.])(?:rc|alpha|beta|dev|pre|preview|snapshot|nightly|test)\d*(?:[-.]|\z)/i

  # [[7, 0, 11], "-slim-bookworm"] for a version tag; nil otherwise.
  def self.parse(tag)
    match = TAG.match(tag.to_s)
    return if match.nil? || match[2].to_s.match?(PRE_RELEASE)

    [ match[1].split(".").map(&:to_i), match[2].to_s.downcase ]
  end

  def self.version_tag?(tag) = !parse(tag).nil?

  # { patch: newest tag of the same series (major.minor) if newer,
  #   major: newest tag of the same major if its minor is newer } — nils dropped.
  def self.newer(tag, tags)
    numbers, variant = parse(tag)
    return {} unless numbers

    same_shape = tags.filter_map { |candidate| (parsed = parse(candidate)) && parsed.last == variant && parsed.first.size == numbers.size && [ parsed.first, candidate ] }
    newer = same_shape.select { |candidate_numbers, _| (candidate_numbers <=> numbers).positive? && candidate_numbers.first == numbers.first }
    patch = newer.select { |candidate_numbers, _| candidate_numbers.first(2) == numbers.first(2) }.max_by(&:first)
    major = newer.reject { |candidate_numbers, _| candidate_numbers.first(2) == numbers.first(2) }.max_by(&:first)
    { patch: patch&.last, major: major&.last }.compact
  end
end
