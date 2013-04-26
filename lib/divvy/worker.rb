module Divvy
  class Worker
    # The worker number
    attr_reader :number

    # The Unix domain socket file used to communicate with the master process.
    attr_reader :socket

    # Whether verbose log info should be written to stderr.
    attr_accessor :verbose

    # Process::Status object result of reaping the worker.
    attr_reader :status

    # The worker processes's pid. This is $$ when inside the worker process.
    attr_accessor :pid

    def initialize(script, number, socket, verbose = false)
      @script = script
      @number = number
      @socket = socket
      @verbose = verbose
      @pid = nil
      @status = nil
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

      # worker should exit on return
    rescue Exception => boom
      warn "error: worker [#{number}]: #{boom.class} #{boom.to_s}"
      exit 1
    end

    def dequeue
      client = UNIXSocket.new(@socket)
      r, w, e = IO.select([client], nil, [client], nil)
      return if !e.empty?

      if data = client.read(16384)
        Marshal.load(data)
      end
    rescue Errno::ENOENT => boom
      # socket file went away, bail out
    ensure
      client.close if client
    end

    def reap
      if @status.nil? && @pid && Process::waitpid(@pid, Process::WNOHANG)
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

      trap "CHLD", "DEFAULT"
    end

    def log(message)
      return if !verbose
      $stderr.printf("worker [%d]: %s\n", number, message)
    end
  end
end
