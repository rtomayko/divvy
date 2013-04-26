module Trans
  class Worker
    # The worker number
    attr_reader :number

    # The pipe this worker will use to read messages
    attr_reader :input_channel

    # Process::Status object result of reaping the worker.
    attr_reader :status

    # The worker processes's pid. This is $$ when inside the worker process.
    attr_accessor :pid

    # Whether verbose log info should be written to stderr.
    attr_accessor :verbose

    def initialize(script, number, input_channel, verbose = false)
      @script = script
      @number = number
      @input_channel = input_channel
      @verbose = verbose
    end

    def running?
      @pid && @status.nil?
    end

    def spawn
      fail "worker already running" if running?
      @status = nil

      if (@pid = fork).nil?
        @pid = $$
        setup_signal_traps
        yield
        main
        exit 0
      end

      @pid
    end

    def main
      fail "Worker#main called in master process" if !worker_process?

      log "booted with pid #{@pid}"
      @script.after_fork(self)

      while arguments = dequeue
        @script.perform(*arguments)
        break if @shutdown
      end

      @input_channel.close
      log "complete"
    end

    def dequeue
      Marshal.load(@input_channel)
    rescue EOFError
      nil
    end

    def reap
      if @pid && Process::waitpid(@pid, Process::WNOHANG)
        @status = $?
        log "exited, reaped pid #{@pid} (status: #{@status.exitstatus})"
        @status
      end
    end

    def kill(signal)
      fail "worker not running" if @pid.nil?
      log "sending signal #{signal}"
      Process.kill(signal, @pid)
      true
    rescue Errno::ESRCH
      false
    end

    def worker_process?
      @pid == $$
    end

    def setup_signal_traps
      fail "attempt to setup worker signal handling in master" if !worker_process?

      %w[INT TERM QUIT].each do |signal|
        trap signal do
          next if @shutdown
          @shutdown = true
          log "#{signal} received. initiating graceful shutdown..."
        end
      end
    end

    def log(message)
      return if !verbose
      $stderr.printf("worker [%d]: %s\n", number, message)
    end
  end
end
