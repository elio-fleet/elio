# The records that hold encrypted attributes (Active Record Encryption: SSH
# key, API keys, webhooks, 2FA secrets…). Used by `bin/rails elio:reencrypt`
# after a rotation of the primary key: each record is encrypted again with
# the current key, so that the former keys can be removed.
module EncryptedRecords
  module_function

  # The models with encrypted attributes, by name.
  def models
    Rails.application.eager_load!
    ApplicationRecord.descendants.select { |model| model.encrypted_attributes.present? && !model.abstract_class? }
                     .uniq(&:table_name).sort_by(&:name)
  end

  # Encrypts every record again with the current key, without validations
  # nor callbacks (update_columns). { "SshKey" => 1, … }.
  def reencrypt!
    models.to_h do |model|
      count = 0
      model.find_each do |record|
        record.encrypt
        count += 1
      end
      [ model.name, count ]
    end
  end
end
