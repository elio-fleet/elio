# One public key line of an authorized_keys file (see sshd(8), "AUTHORIZED_KEYS FILE FORMAT"):
#
#   [options] keytype base64-key [comment]
#
# The comment is what we call the key's name: a key without one is "unknown".
class AuthorizedKey
  KEY_TYPES = %w[
    ssh-ed25519 ssh-rsa ssh-dss
    ecdsa-sha2-nistp256 ecdsa-sha2-nistp384 ecdsa-sha2-nistp521
    sk-ssh-ed25519@openssh.com sk-ecdsa-sha2-nistp256@openssh.com
  ].freeze

  LINE_REGEXP = /
    \A(?:(?<options>.*?)\s+)?                                     # optional options, e.g. from="10.0.0.1",no-pty
    (?<type>#{KEY_TYPES.map { |type| Regexp.escape(type) }.join("|")})
    \s+(?<key>[A-Za-z0-9+\/]+={0,2})
    (?:\s+(?<comment>.*))?\z
  /x

  attr_reader :type, :key, :comment, :options, :line_number

  # Parses the content of an authorized_keys file, skipping blank lines,
  # comments and lines that are not valid keys.
  def self.parse(content)
    content.to_s.each_line.with_index(1).filter_map do |line, line_number|
      line = line.strip
      next if line.empty? || line.start_with?("#")

      match = LINE_REGEXP.match(line)
      next unless match && valid_blob?(match[:type], match[:key])

      new(type: match[:type], key: match[:key], comment: match[:comment], options: match[:options], line_number: line_number)
    end
  end

  # The base64 blob must decode and start with its own key type.
  def self.valid_blob?(type, key)
    blob = Base64.strict_decode64(key)
    Net::SSH::Buffer.new(blob).read_string == type
  rescue ArgumentError, Net::SSH::Exception
    false
  end
  private_class_method :valid_blob?

  def initialize(type:, key:, comment: nil, options: nil, line_number: nil)
    @type = type
    @key = key
    @comment = comment&.strip.presence
    @options = options&.strip.presence
    @line_number = line_number
  end

  def name = comment

  # The authorized_keys line for this key.
  def to_line = [ options, type, key, comment ].compact.join(" ")

  def named? = comment.present?

  def fingerprint
    Ssh::KeyGenerator.fingerprint(Base64.strict_decode64(key))
  end

  # Below this size an RSA key is weak (NIST SP 800-57: 3072 bits for use past 2030).
  RSA_MIN_BITS = 3072

  # Why the key is weak, or nil: :dsa (refused by OpenSSH since 7.0) or
  # :rsa_short (fewer than RSA_MIN_BITS bits). The SHA-1 signature of the old
  # ssh-rsa algorithm is chosen by the client at each connection, so it cannot
  # be read from the public key: an RSA key of enough bits is not flagged.
  def weakness
    return :dsa if type == "ssh-dss"

    :rsa_short if type == "ssh-rsa" && rsa_bits.to_i.between?(1, RSA_MIN_BITS - 1)
  end

  def weak? = weakness.present?

  # Size of an RSA key's modulus, nil for another type.
  def rsa_bits
    return unless type == "ssh-rsa"

    @rsa_bits ||= Net::SSH::Buffer.new(Base64.strict_decode64(key)).read_key.n.num_bits
  end

  # True when this is the public key of the given SshKey, or of one of them
  # (compared on the key itself, not the comment, which anyone can change).
  def matches?(ssh_keys)
    Array(ssh_keys).compact.any? do |ssh_key|
      other_type, other_key = ssh_key.public_key.split(" ")
      type == other_type && key == other_key
    end
  end

  # The options in front of the key, in order (sshd(8), "AUTHORIZED_KEYS FILE
  # FORMAT"): [["from", "10.0.0.0/8"], ["no-pty", nil], …], names in lower
  # case, values without their quotes. A comma inside quotes does not split.
  def option_list
    @option_list ||= options.to_s.scan(/(?:[^,"]|"(?:\\.|[^"\\])*"?)+/).map do |option|
      name, value = option.split("=", 2)
      [ name.strip.downcase, value&.strip&.delete_prefix('"')&.delete_suffix('"')&.gsub('\\"', '"') ]
    end
  end

  # The value of an option (the first one when repeated), nil when absent.
  def option(name) = option_list.find { |option_name, _| option_name == name }&.last

  # When sshd stops accepting the key (expiry-time="YYYYMMDD[HHMM[SS]][Z]"),
  # nil without a valid one. Without Z sshd reads the server's local time,
  # which Elio does not know: read as UTC, see #expiry_local_time?.
  def expires_at
    match = option("expiry-time").to_s.match(/\A(\d{8})(\d{4})?(\d{2})?Z?\z/)
    return unless match

    Time.find_zone("UTC").strptime("#{match[1]}#{match[2] || "0000"}#{match[3] || "00"}", "%Y%m%d%H%M%S")
  rescue ArgumentError
    nil
  end

  def expiry_local_time? = expires_at.present? && !option("expiry-time").end_with?("Z")
end
