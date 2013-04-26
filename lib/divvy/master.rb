require 'socket'

module Divvy
  class Master
    attr_accessor :verbose

    attr_reader :workers
    attr_reader :worker_count
    attr_reader :socket

    # Exception raised when a graceful shutdown signal is received.
    class Shutdown < StandardError
    end

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

    # Initiate shutdown of the run loop. The loop will not be stopped when this
    # method returns. The original run loop will return after the current iteration
    # of task item.
    def shutdown
      @shutdown = true
    end

    def start_server
      File.unlink(@socket) if File.exist?(@socket)
      @server = UNIXServer.new(@socket)
      @server.listen(worker_count)
    end

    def stop_server
      File.unlink(@socket) if File.exist?(@socket)
      @server.close if @server
      @server = nil
    end

    def boot_workers
      workers.each do |worker|
        next if worker.running?
        boot_worker(worker)
      end
    end

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

    def kill_workers(signal = 'TERM')
      workers.each do |worker|
        next if !worker.running?
        worker.kill(signal)
      end
    end

    def reap_workers
      @reap = false
      workers.select { |worker| worker.reap }
    end

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

    def log(message)
      return if !verbose
      $stderr.printf("master: %s\n", message)
    end
  end
end
