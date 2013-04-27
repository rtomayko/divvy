module Divvy
  # Models an individual divvy worker process. These objects are used in both
  # the master and the forked off workers to perform common tasks and for basic
  # tracking.
  class Worker
    # The worker number. These are sequential starting from 1 and ending in the
    # configured worker concurrency count.
    attr_reader :number

    # The Unix domain socket file used to communicate with the master process.
    attr_reader :socket

    # Whether verbose log info should be written to stderr.
    attr_accessor :verbose

    # Process::Status object result of reaping the worker.
    attr_reader :status

    # The worker processes's pid. This is $$ when inside the worker process.
    attr_accessor :pid

    # Create a Worker object. The Master object typically handles this.
    def initialize(task, number, socket, verbose = false)
      @task = task
      @number = number
      @socket = socket
      @verbose = verbose
      @pid = nil
      @status = nil
    end

    # Public: Check whether the worker process is thought to be running. This
    # does not attempt to verify the real state of the process with the system.
    def running?
      @pid && @status.nil?
    end

    # Public: Send a signal to a running worker process.
    #
    # signal - String signal name.
    #
    # Returns true when the process was signaled, false if the process is no
    # longer running.
    # Raises when the worker process is not thought to be running.
    def kill(signal)
      fail "worker not running" if @pid.nil?
      log "sending signal #{signal}"
      Process.kill(signal, @pid)
      true
    rescue Errno::ESRCH
      false
    end

    # Public: Check whether the current process is this worker process.
    #
    # Returns true when we're in this worker, false in the master.
    def worker_process?
      @pid == $$
    end

    # Public: Fork off a new process for this worker and yield to the block
    # immediately in the new child process.
    #
    # Returns the pid of the new process in the master process. Never returns in
    # the child process.
    # Raises when the worker process is already thought to be running or has not
    # yet been reaped.
    def spawn
      fail "worker already running" if running?
      @status = nil

      if (@pid = fork).nil?
        @pid = $$
        yield
        install_signal_traps
        main
        exit 0
      end

      @pid
    end

    # Public: Attempt to reap this worker's process using waitpid. This is a
    # no-op if the process is not thought to be running or is marked as already
    # being reaped. This should only be called in the master process.
    #
    # Returns the Process::Status object if the process was reaped, nil if the
    # process was not reaped because it's still running or is already reaped.
    def reap
      if @status.nil? && @pid && Process::waitpid(@pid, Process::WNOHANG)
        @status = $?
        log "exited, reaped pid #{@pid} (status: #{@status.exitstatus})"
        @status
      end
    end

    # Internal: The main worker loop. This is called after a new worker process
    # has been setup with signal traps and whatnot and connects to the master in
    # a loop to retrieve task items. The worker process exits if this method
    # returns or raises an exception.
    def main
      fail "Worker#main called in master process" if !worker_process?

      log "booted with pid #{@pid}"
      @task.after_fork(self)

      while arguments = dequeue
        @task.process(*arguments)
        break if @shutdown
      end

      # worker should exit on return
    rescue Exception => boom
      message = "error: worker [#{number}]: #{boom.class} #{boom.to_s}"
      if verbose || ENV['DIVVY_VERBOSE_TRACE']
        backtrace = boom.backtrace.join("\n").gsub(/^/, "  ").gsub("#{Dir.pwd}/", "")
        message << "\n#{backtrace}"
      end
      $stderr.puts message
      exit 1
    end

    # Internal: Retrieve an individual task item from the master process. Opens
    # a new socket, reads and unmarshals a single task item.
    #
    # Returns an Array containing the arguments yielded by the dispatcher.
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

    def install_signal_traps
      fail "attempt to install worker signal handling in master" if !worker_process?

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
