require 'socket'

module Divvy
  # The master process used to generate and distribute task items to the
  # worker processes.
  class Master
    # The number of worker processes to boot.
    attr_reader :worker_count

    # The array of Worker objects this master is managing.
    attr_reader :workers

    # The string filename of the unix domain socket used to distribute work.
    attr_reader :socket

    # Enable verbose logging to stderr.
    attr_accessor :verbose

    # Number of tasks that have been distributed to worker processes.
    attr_reader :tasks_distributed

    # Number of worker processes that have exited with a failure status since
    # the master started processing work.
    attr_reader :failures

    # Number of worker processes that have been spawned since the master
    # started processing work.
    attr_reader :spawn_count

    # Raised from a signal handler when a forceful shutdown is requested.
    class Shutdown < Exception
    end

    # Raised from the run loop when worker processes never fully booted and
    # started making connections to the master.
    class BootFailure < StandardError
    end

    # Create the master process object.
    #
    # task         - Object that implements the Parallelizable interface.
    # worker_count - Number of worker processes.
    # verbose      - Enable verbose error logging.
    # socket       - The unix domain socket filename.
    #
    # The workers array is initialized with Worker objects for the number of
    # worker processes requested. The processes are not actually started at this
    # time though.
    def initialize(task, worker_count, verbose = false, socket = nil)
      @task = task
      @worker_count = worker_count
      @verbose = verbose
      @socket = socket || "/tmp/divvy-#{$$}-#{object_id}.sock"

      # stats
      @tasks_distributed = 0
      @failures = 0
      @spawn_count = 0

      # shutdown state
      @shutdown = false
      @graceful = true
      @reap = false

      # worker objects
      @workers = []
      (1..@worker_count).each do |worker_num|
        worker = Divvy::Worker.new(@task, worker_num, @socket, @verbose)
        workers << worker
      end
    end

    # Public: Start the main run loop. This installs signal handlers into the
    # current process, binds to the unix domain socket, boots workers, and begins
    # dispatching work.
    #
    # The run method does not return until all task items generated have been
    # processed unless a shutdown signal is received or the #shutdown method is
    # called within the loop.
    #
    # Returns nothing.
    # Raises BootFailure when the workers fail to start.
    # Raises Shutdown when a forceful shutdown is triggered (SIGTERM).
    def run
      fail "Already running!!!" if @server
      fail "Attempt to run master in a worker process" if worker_process?
      install_signal_traps
      start_server

      @task.dispatch do |*task_item|
        # boot workers that haven't started yet or have been reaped
        boot_workers

        # check for shutdown or worker reap flag until a connection is pending
        # in the domain socket queue. bail out if workers exited before even
        # requesting a task item.
        while IO.select([@server], nil, nil, 0.010).nil?
          break if @shutdown
          if @reap
            reap_workers
            if !workers_running? && @tasks_distributed == 0
              raise BootFailure, "Worker processes failed to boot."
            else
              boot_workers
            end
          end
        end
        break if @shutdown

        # at this point there should be at least one connection pending.
        begin
          data = Marshal.dump(task_item)
          sock = @server.accept
          sock.write(data)
        ensure
          sock.close if sock
        end
        @tasks_distributed += 1

        break if @shutdown
        reap_workers if @reap
      end

      nil
    rescue Shutdown
      @graceful = false
      @shutdown = true
    ensure
      shutdown! if master_process?
    end

    # Public: Check if the current process is the master process.
    #
    # Returns true in the master process, false in the worker process.
    def master_process?
      @workers
    end

    # Public: Check if the current process is a worker process.
    # This relies on the @workers array being set to a nil value.
    #
    # Returns true in the worker process, false in master processes.
    def worker_process?
      !master_process?
    end

    # Public: Are any worker processes currently running or have yet to be
    # reaped by the master process?
    def workers_running?
      @workers.any? { |worker| worker.running? }
    end

    # Public: Initiate shutdown of the run loop. The loop will not be stopped when
    # this method returns. The original run loop will return after the current
    # iteration of task item.
    def shutdown
      @shutdown ||= Time.now
    end

    # Internal: Really shutdown the unix socket and reap all worker processes.
    # This doesn't signal the workers. Instead, the socket shutdown is relied
    # upon to trigger the workers to exit normally.
    #
    # TODO Send SIGKILL when workers stay running for configurable period.
    def shutdown!
      fail "Master#shutdown! called in worker process" if worker_process?
      stop_server
      while workers_running?
        kill_workers("KILL") if !@graceful
        reaped = reap_workers
        sleep 0.010 if reaped.empty?
      end
      reset_signal_traps
      raise Shutdown if !@graceful
    end

    # Internal: create and bind to the unix domain socket. Note that the
    # requested backlog matches the number of workers. Otherwise workers will
    # get ECONNREFUSED when attempting to connect to the master and exit.
    def start_server
      fail "Master#start_server called in worker process" if worker_process?
      File.unlink(@socket) if File.exist?(@socket)
      @server = UNIXServer.new(@socket)
      @server.listen(worker_count)
    end

    # Internal: Close and remove the unix domain socket.
    def stop_server
      fail "Master#stop_server called in worker process" if worker_process?
      File.unlink(@socket) if File.exist?(@socket)
      @server.close if @server
      @server = nil
    end

    # Internal: Boot any workers that are not currently running. This is a no-op
    # if all workers are though to be running. No attempt is made to verify
    # worker processes are running here. Only workers that have not yet been
    # booted and those previously marked as reaped are started.
    def boot_workers
      workers.each do |worker|
        next if worker.running?
        boot_worker(worker)
      end
    end

    # Internal: Boot and individual worker process. Don't call this if the
    # worker is thought to be running.
    #
    # worker - The Worker object to boot.
    #
    # Returns the Worker object provided.
    def boot_worker(worker)
      fail "worker #{worker.number} already running" if worker.running?

      @task.before_fork(worker)

      worker.spawn do
        reset_signal_traps
        @workers = nil

        @server.close
        @server = nil

        $stdin.close
      end
      @spawn_count += 1

      worker
    end

    # Internal: Send a signal to all running workers.
    #
    # signal - The string signal name.
    #
    # Returns nothing.
    def kill_workers(signal = 'TERM')
      workers.each do |worker|
        next if !worker.running?
        worker.kill(signal)
      end
    end

    # Internal: Attempt to reap all worker processes via Process::waitpid. This
    # method does not block waiting for processes to exit. Running processes are
    # ignored.
    #
    # Returns an array of Worker objects whose process's were reaped. The
    # Worker#status attribute can be used to access the Process::Status result.
    def reap_workers
      @reap = false
      workers.select do |worker|
        if status = worker.reap
          @failures += 1 if !status.success?
          worker
        end
      end
    end

    # Internal: Install traps for shutdown signals. Most signals deal with
    # shutting down the master loop and socket.
    #
    # INFO      - Dump stack for all processes to stderr.
    # TERM      - Initiate immediate forceful shutdown of all worker processes
    #             along with the master process, aborting any existing jobs in
    #             progress.
    # INT, QUIT - Initiate graceful shutdown, allowing existing worker processes
    #             to finish their current task and exit on their own. If this
    #             signal is received again after 10s, instead initiate an
    #             immediate forceful shutdown as with TERM. This is mostly so you
    #             can interrupt sanely with Ctrl+C with the master foregrounded.
    # CHLD      - Set the worker reap flag. An attempt is made to reap workers
    #             immediately after the current dispatch iteration.
    #
    # Returns nothing.
    def install_signal_traps
      @traps =
        %w[INT QUIT].map do |signal|
          Signal.trap signal do
            if @shutdown
              raise Shutdown, "SIG#{signal}" if (Time.now - @shutdown) > 10 # seconds
              next
            else
              shutdown
              log "#{signal} received. initiating graceful shutdown..."
            end
          end
        end
      @traps << Signal.trap("CHLD") { @reap = true }
      @traps << Signal.trap("TERM") { raise Shutdown, "SIGTERM" }

      Signal.trap "INFO" do
        message = "==> info: process #$$ dumping stack\n"
        message << caller.join("\n").gsub(/^/, "    ").gsub("#{Dir.pwd}/", "")
        $stderr.puts(message)
      end
    end

    # Internal: Uninstall signal traps set up by the install_signal_traps
    # method. This is called immediately after forking worker processes to reset
    # traps to their default implementations and also when the master process
    # shuts down.
    def reset_signal_traps
      %w[INT TERM QUIT CHLD].each do |signal|
        handler = @traps.shift || "DEFAULT"
        if handler.is_a?(String)
          Signal.trap(signal, handler)
        else
          Signal.trap(signal, &handler)
        end
      end
    end

    # Internal: Write a verbose log message to stderr.
    def log(message)
      return if !verbose
      $stderr.printf("master: %s\n", message)
    end
  end
end
