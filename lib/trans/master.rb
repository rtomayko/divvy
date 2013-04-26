module Trans
  class Master
    attr_accessor :verbose

    attr_reader :workers
    attr_reader :worker_count
    attr_reader :input_read

    # Exception raised when a graceful shutdown signal is received.
    class Shutdown < StandardError
    end

    def initialize(script, worker_count, verbose = false)
      @script = script
      @worker_count = worker_count
      @verbose = verbose

      @input_read, @input_write = IO.pipe
      @input_read.sync = @input_write.sync = true

      @shutdown = false
      @reap = false

      @workers = []
      (1..@worker_count).each do |worker_num|
        worker = Trans::Worker.new(@script, worker_num, @input_read, @verbose)
        workers << worker
      end
    end

    def main
      setup_signal_traps

      @script.dispatch do |*arguments|
        boot_workers

        data = Marshal.dump(arguments)
        @input_write.write(data)
        @input_write.flush

        break if @shutdown
      end

      @input_write.close
      @input_read.close

    ensure
      while workers.any? { |worker| worker.running? }
        reap_workers
        sleep 0.010
      end
    end

    def boot_workers
      workers.each do |worker|
        next if worker.running?
        boot_worker(worker)
      end
    end

    def boot_worker(worker)
      fail "worker #{worker.number} already running" if worker.running?

      @script.before_fork(worker)

      worker.spawn do
        @workers = []
        @input_write.close
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

    def setup_signal_traps
      %w[INT TERM QUIT].each do |signal|
        Signal.trap signal do
          next if @shutdown
          @shutdown = true
          log "#{signal} received. initiating graceful shutdown..."
        end
      end

      Signal.trap("CHLD") { @reap = true }
    end

    def log(message)
      return if !verbose
      $stderr.printf("master: %s\n", message)
    end
  end
end
