# Stubs of Keys::AuthorizedKeysReader.call_all (every account of a server)
# built from a login-account Result, as the tests read one account:
#
#   stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(result))
#   stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(result, others: { "root" => [ line ] }))
#
# `result` may be a Result or a lambda returning one; `others` (user =>
# lines) are the accounts read through root (privileged).
module KeysReaderHelpers
  def keys_read(result, others: nil)
    lambda do |server, **options|
      read = result.respond_to?(:call) ? result.call(server, account: AuthorizedKeysAccount.login(server), **options) : result
      next Keys::AuthorizedKeysReader::All.new(accounts: [], privileged: false, error_title: read.error_title, error_details: read.error_details, reason: read.reason) unless read.success?

      reader = Keys::AuthorizedKeysReader
      accounts = [ reader::AccountKeys.new(account: AuthorizedKeysAccount.login(server), keys: read.keys) ]
      accounts += others.to_h.map { |user, lines| reader::AccountKeys.new(account: AuthorizedKeysAccount.new(server, user), keys: AuthorizedKey.parse(Array(lines).join("\n"))) }
      reader::All.new(accounts: accounts, privileged: !others.nil?)
    end
  end
end

ActiveSupport.on_load(:active_support_test_case) { include KeysReaderHelpers }
