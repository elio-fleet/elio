module Elio
  # The whole-number environment variables, checked when Elio starts
  # (config/initializers/env.rb): a typo such as ELIO_PARALLEL_LIMIT=four
  # stops the start with a message that names the variable, instead of a bare
  # Ruby error, or a value silently read as 0 (ELIO_ACTIVITY_RETENTION_DAYS=1y
  # kept the activity log forever).
  module Env
    class Invalid < StandardError; end

    # Variable => [default, minimum].
    INTEGERS = { "ELIO_PARALLEL_LIMIT" => [ 4, 1 ], "ELIO_ACTIVITY_RETENTION_DAYS" => [ 365, 0 ], "SMTP_PORT" => [ 587, 1 ] }.freeze

    module_function

    # The value of a variable of INTEGERS, its default when it is not set.
    def integer(name, env = ENV)
      default, minimum = INTEGERS.fetch(name)
      raw = env[name].to_s.strip
      return default if raw.empty?

      value = Integer(raw, 10, exception: false)
      return value if value && value >= minimum

      raise Invalid, "#{name}=#{raw.inspect} is not valid: expected a whole number, #{minimum} or more (#{default} when it is not set)"
    end

    def validate!(env = ENV) = INTEGERS.each_key { |name| integer(name, env) }
  end
end
