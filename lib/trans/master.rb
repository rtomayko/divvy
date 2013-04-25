module Trans
  class Master
    attr_reader :workers
    attr_reader :worker_count
    attr_reader :input_read

    # Exception raised when a graceful shutdown signal is received.
    class Shutdown < StandardError
    end

    def initialize(script, worker_count)
      @script = script
      @worker_count = worker_count

      @input_read, @input_write = IO.pipe
      @input_read.sync = @input_write.sync = true

      @shutdown = false

      @workers = []
      (1..@worker_count).each do |worker_num|
        worker = Trans::Worker.new(@script, worker_num, @input_read)
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

        reap_workers
      end

      @input_write.close
      @input_read.close

      while workers.any? { |worker| worker.running? }
        reap_workers
        sleep 1
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
        $stdin.close
        @input_write.close
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
    end

    def log(message)
      warn "master: #{message}"
    end
  end
end
