module Trans
  class Worker
    # The worker number
    attr_reader :number

    # The pipe this worker will use to read messages
    attr_reader :input_channel

    # Process::Status object result of reaping the worker.
    attr_reader :status

    # The worker processes's pid. This is $! when inside the worker process.
    attr_accessor :pid

    def initialize(script, number, input_channel)
      @script = script
      @number = number
      @input_channel = input_channel
    end

    def running?
      @pid && @status.nil?
    end

    def spawn
      fail "worker already running" if running?
      @status = nil
      @pid = fork { yield }
      log "booted with pid #{@pid}"
      @pid
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

    def log(message)
      warn "worker [#{number}]: #{message}"
    end
  end
end
