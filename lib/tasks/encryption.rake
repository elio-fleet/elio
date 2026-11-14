namespace :elio do
  desc "Encrypt the secrets of the database again with the current primary key (after a key rotation, see README)"
  task reencrypt: :environment do
    EncryptedRecords.reencrypt!.each { |model, count| puts "#{model}: #{count} record(s) encrypted again" }
    puts "Done: the former keys (ACTIVE_RECORD_ENCRYPTION_PREVIOUS_PRIMARY_KEYS) can now be removed."
  end
end
