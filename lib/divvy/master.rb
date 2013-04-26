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

      @shutdown = false
      @reap = false

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
    def run
      install_signal_traps
      start_server

      @task.dispatch do |*task_item|
        boot_workers

        data = Marshal.dump(task_item)

        begin
          sock = @server.accept
          sock.write(data)
        ensure
          sock.close if sock
        end

        break if @shutdown
        reap_workers if @reap
      end
      nil
    ensure
      if !workers.empty?
        reset_signal_traps
        stop_server
        while workers.any? { |worker| worker.running? }
          reap_workers
          sleep 0.010
          # TODO send TERM when workers won't reap for some amount of time
        end
      end
    end

    # Public: Initiate shutdown of the run loop. The loop will not be stopped when
    # this method returns. The original run loop will return after the current
    # iteration of task item.
    def shutdown
      @shutdown = true
    end

    # Internal: create and bind to the unix domain socket. Note that the
    # requested backlog matches the number of workers. Otherwise workers will
    # get ECONNREFUSED when attempting to connect to the master and exit.
    def start_server
      File.unlink(@socket) if File.exist?(@socket)
      @server = UNIXServer.new(@socket)
      @server.listen(worker_count)
    end

    # Internal: Close and remove the unix domain socket.
    def stop_server
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
        @workers = []

        @server.close
        @server = nil

        $stdin.close
      end

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
      workers.select { |worker| worker.reap }
    end

    # Internal: Install traps for shutdown signals. This triggers a shutdown of
    # the main loop any time an INT, TERM, or QUIT signal is recieved by the
    # master process. The CHLD signal is trapped to initiate reaping of worker
    # processes.
    def install_signal_traps
      @traps =
        %w[INT TERM QUIT].map do |signal|
          Signal.trap signal do
            next if @shutdown
            shutdown
            log "#{signal} received. initiating graceful shutdown..."
          end
        end
      @traps << Signal.trap("CHLD") { @reap = true }
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
