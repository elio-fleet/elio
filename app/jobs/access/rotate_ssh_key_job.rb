# Rotates Elio's key on every server (see KeyRotation), through the account
# Elio logs in as: install the new key with the old one, then, on a single
# connection opened with the new key (which proves it works), check a login
# and remove the old key. Both connections hold the server's key lock
# (Keys::WriteSession).
#
# Only the servers without a step yet are done, so a run interrupted (Elio
# restarted, job lost) resumes where it stopped, and servers added meanwhile
# are not forgotten; retry_failed first forgets the failed steps. Two runs of
# one rotation never overlap.
class RotateSshKeyJob < ApplicationJob
  class StepFailed < StandardError
    attr_reader :phase

    def initialize(phase, message)
      @phase = phase
      super(message)
    end
  end

  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(rotation, retry_failed: false)
    AdvisoryLock.try("key_rotation:#{rotation.id}") do
      next if rotation.reload.activated?

      Current.user = rotation.started_by
      rotation.steps.failed.delete_all if retry_failed
      rotation.update!(finished_at: nil) if rotation.finished_at

      while (servers = remaining_servers(rotation)).any?
        rotation.update!(servers_count: rotation.steps.count + servers.size)
        servers.each { |server| rotate(rotation, server) }
      end
      rotation.finish!
    end
  ensure
    Current.reset
  end

  private

  def remaining_servers(rotation)
    Server.where.not(id: rotation.steps.where.not(server_id: nil).select(:server_id)).order(:name).to_a
  end

  def rotate(rotation, server)
    account = AuthorizedKeysAccount.login(server)
    install(rotation, server)
    verify_and_cleanup(rotation, server, account)
    rotation.steps.create!(server: server, server_name: server.name, status: :rotated)
  rescue StepFailed => e
    rotation.steps.create!(server: server, server_name: server.name, status: :failed, phase: e.phase, error_message: e.message)
  end

  def install(rotation, server)
    new_key = rotation.new_key
    Keys::WriteSession.open(server, key: [ rotation.old_key, new_key ]) { |ssh| ssh.run_command!("keys.append", line: new_key.public_key, blob: new_key.blob) }
  rescue Ssh::Connection::Error => e
    raise StepFailed.new("install", "#{e.title} — #{e.message}")
  end

  # The connection only offers the new key: if it opens, the new key works.
  def verify_and_cleanup(rotation, server, account)
    removal = Keys::WriteSession.open(server, key: rotation.new_key) do |ssh|
      check = Ssh::Check.call(server, ssh: ssh)
      raise StepFailed.new("verify", "#{check.message} — #{check.details}") unless check.success?
      next unless rotation.old_key

      Keys::AuthorizedKeyRemoval.call(server, rotation.old_key.blob, account: account, protected_keys: [ rotation.new_key ], ssh: ssh)
    end
    raise StepFailed.new("cleanup", "#{removal.error_title} — #{removal.error_details}") if removal && !removal.success?
  rescue Ssh::Connection::Error => e
    raise StepFailed.new("verify", "#{e.title} — #{e.message}")
  end
end
