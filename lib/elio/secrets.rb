require "securerandom"

module Elio
  # Secrets of an installation: Rails' secret_key_base and the keys of Active
  # Record Encryption (SSH key, webhooks, API keys, 2FA secrets in the
  # database). Read from environment variables, so that any installation (the
  # Docker image, a clone) has its own without editing Rails credentials;
  # credentials stay the fallback of the installations that already use them.
  module Secrets
    ENCRYPTION = { primary_key: "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY", deterministic_key: "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY",
                   key_derivation_salt: "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" }.freeze

    # Former primary keys, comma-separated, during a key rotation: still read,
    # never used to encrypt (`bin/rails elio:reencrypt` moves the data to the
    # current key, then they can be removed).
    PREVIOUS_PRIMARY_KEYS = "ACTIVE_RECORD_ENCRYPTION_PREVIOUS_PRIMARY_KEYS"

    module_function

    # { primary_key: "…", … } for the variables that are set. With former
    # primary keys, primary_key is a list ending with the current one: Rails
    # encrypts with the last key and tries each of them to decrypt.
    def encryption_keys(env = ENV)
      keys = ENCRYPTION.filter_map { |key, variable| [ key, env[variable] ] if env[variable].to_s.strip != "" }.to_h
      previous = env[PREVIOUS_PRIMARY_KEYS].to_s.split(",").map(&:strip).reject(&:empty?)
      keys[:primary_key] = [ *previous, keys[:primary_key] ].uniq if keys[:primary_key] && previous.any?
      keys
    end

    # A fresh set of variables, as `bin/elio-keys` prints them.
    def generate
      { "SECRET_KEY_BASE" => SecureRandom.hex(64) }.merge(ENCRYPTION.values.to_h { |variable| [ variable, SecureRandom.alphanumeric(32) ] })
    end
  end
end
