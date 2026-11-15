require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  test "the fleet columns hidden by the user: known columns only, kept in the preferences" do
    user = users(:viewer)
    assert user.fleet_column?(:load)

    user.hide_fleet_columns!([ "load", :notes, "password" ])

    assert_equal %w[load notes], user.reload.hidden_fleet_columns
    assert_not user.fleet_column?(:load)
    assert user.fleet_column?("disk")
    user.update_column(:preferences, { "hidden_fleet_columns" => "load" })
    assert_equal %w[load], user.reload.hidden_fleet_columns, "a damaged value does not break the list"
  end

  test "is valid with an email and a password" do
    user = User.new(email: "valid@example.com", password: "password1234")
    assert user.valid?
  end

  test "requires an email" do
    user = User.new(password: "password1234")
    assert_not user.valid?
    assert user.errors.added?(:email, :blank)
  end

  test "requires a unique email (case insensitive)" do
    user = User.new(email: users(:one).email.upcase, password: "password1234")
    assert_not user.valid?
    assert user.errors.added?(:email, :taken, value: users(:one).email)
  end

  test "requires a password of at least 6 characters" do
    user = User.new(email: "short@example.com", password: "12345")
    assert_not user.valid?
    assert user.errors.of_kind?(:password, :too_short)
  end

  test "authenticates with the correct password only" do
    assert users(:one).valid_password?("password1234")
    assert_not users(:one).valid_password?("wrong")
  end

  test "new users are viewers by default" do
    assert User.new.viewer?
  end

  test "rejects an unknown role" do
    user = User.new(email: "x@example.com", password: "password1234", role: "root")
    assert_not user.valid?
    assert user.errors.key?(:role)
  end

  test "permissions per role" do
    assert_equal [ true, true, true ], %i[view operate administer].map { |permission| users(:one).can?(permission) }
    assert_equal [ true, true, false ], %i[view operate administer].map { |permission| users(:operator).can?(permission) }
    assert_equal [ true, false, false ], %i[view operate administer].map { |permission| users(:viewer).can?(permission) }
    assert_raises(KeyError) { users(:one).can?(:nope) }
  end

  test "role labels" do
    assert_equal %w[Admin Opérateur Lecture], [ users(:one), users(:operator), users(:viewer) ].map(&:role_label)
  end

  test "a deactivated account cannot authenticate" do
    user = users(:operator)
    assert user.active_for_authentication?

    user.deactivate!

    assert user.deactivated?
    assert_not user.active_for_authentication?
    assert_equal :deactivated, user.inactive_message
    assert_not_includes User.active, user

    user.reactivate!
    assert user.active_for_authentication?
  end

  test "the last active admin cannot be demoted or deactivated" do
    admin = users(:one)

    assert_not admin.update(role: :operator)
    assert_includes admin.errors.full_messages, "Il doit toujours rester au moins un administrateur actif."

    admin.reload
    assert_raises(ActiveRecord::RecordInvalid) { admin.deactivate! }
  end

  test "an admin can be demoted when another active admin remains" do
    users(:operator).update!(role: :admin)

    assert users(:one).update(role: :viewer)
  end

  test "a deactivated admin does not count as remaining admin" do
    other = users(:operator)
    other.update!(role: :admin)
    other.deactivate!

    assert_not users(:one).update(role: :viewer)
  end

  test "a requested password change needs a different password, and ends once it is chosen" do
    user = users(:viewer)
    user.require_password_change!
    assert user.reload.password_change_required?

    assert_not user.update(password: "password1234", password_confirmation: "password1234")
    assert_includes user.errors.details[:password], { error: :same_as_before }
    user.reload

    user.update!(password: "new-password-5678", password_confirmation: "new-password-5678")
    assert_not user.reload.password_change_required?
    assert user.valid_password?("new-password-5678")
  end

  test "a password reset by email also ends a requested password change" do
    user = users(:viewer)
    user.require_password_change!

    user.reset_password("new-password-5678", "new-password-5678")

    assert_not user.reload.password_change_required?
  end

  test "other changes keep the requested password change" do
    user = users(:viewer)
    user.require_password_change!

    user.update!(locale: "en")

    assert user.reload.password_change_required?
  end

  test "locking logs an activity and sends no email" do
    assert_no_emails do
      users(:viewer).lock_access!
    end

    assert users(:viewer).access_locked?
    assert_not users(:viewer).active_for_authentication?
    assert_equal :locked, users(:viewer).inactive_message
    assert_equal 1, Activity.of_kind(:user_locked).count
  end

  test "failed 2FA attempts lock the account after the maximum" do
    user = users(:viewer)
    (Devise.maximum_attempts - 1).times { user.register_failed_two_factor_attempt! }
    assert_not user.access_locked?

    user.register_failed_two_factor_attempt!
    assert user.access_locked?
  end
end
