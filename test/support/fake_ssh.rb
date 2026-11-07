# In-memory stand-in for Net::SSH, used through Ssh::Connection's `transport:`.
class FakeSsh
  # `hang: true` keeps the command running forever (to test timeouts).
  Response = Struct.new(:stdout, :stderr, :exit_status, :hang)

  attr_reader :started_with, :commands, :sessions

  # `handler` computes a Response from the command when it is not in `responses`.
  def initialize(responses: {}, handler: nil, error: nil)
    @responses = responses
    @handler = handler
    @error = error
    @commands = []
    @sessions = []
  end

  # Net::SSH.start(host, user, **options) { |session| ... }
  def start(host, user, **options)
    @started_with = { host: host, user: user, **options }
    raise @error if @error

    session = Session.new(self)
    @sessions << session
    yield session
  end

  def response_for(command)
    @commands << command
    @responses.fetch(command) { @handler&.call(command) || Response.new("", "#{command}: command not found\n", 127) }
  end

  # Net::SSH::Connection::Session: open_channel, loop, shutdown!.
  class Session
    def initialize(fake)
      @fake = fake
      @shut_down = false
    end

    def shut_down? = @shut_down

    def open_channel
      Channel.new(@fake).tap { |channel| yield channel }
    end

    # Runs the event loop while the block is true (here: until the command
    # ends, or forever for a hanging one).
    def loop(wait = nil)
      while yield
        sleep(wait || 0.01)
      end
    end

    def shutdown!
      @shut_down = true
    end
  end

  # Net::SSH::Connection::Channel: exec, on_data, on_extended_data,
  # on_request("exit-status"), active?.
  class Channel
    ExitStatus = Struct.new(:read_long)

    def initialize(fake)
      @fake = fake
      @active = true
      @callbacks = {}
    end

    def active? = @active

    def exec(command)
      response = @fake.response_for(command)
      yield self, true
      return if response.hang

      # Like net-ssh: BINARY chunks, possibly cut inside a character.
      response.stdout.to_s.b.each_char.each_slice(7) { |chunk| @callbacks[:data]&.call(self, chunk.join.b) }
      @callbacks[:extended_data]&.call(self, 1, response.stderr.to_s.b) unless response.stderr.to_s.empty?
      @callbacks[:exit_status]&.call(self, ExitStatus.new(response.exit_status))
      @active = false
    end

    def on_data(&block) = @callbacks[:data] = block
    def on_extended_data(&block) = @callbacks[:extended_data] = block

    def on_request(name, &block)
      @callbacks[:exit_status] = block if name == "exit-status"
    end
  end
end
