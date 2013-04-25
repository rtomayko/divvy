module Trans
  class Master
    attr_reader :worker_count
    attr_reader :input_read

    def initialize(script, worker_count)
      @script = script
      @worker_count = worker_count

      @input_read, @input_write = IO.pipe
      @input_read.sync = @input_write.sync = true

      initialize_workers
    end

    def initialize_workers
      @workers = []
      (1..@worker_count).each do |worker_num|
        worker = Trans::Worker.new(@script, worker_num, @input_read)
        workers << worker
      end
    end

    def main
      @script.dispatch do |*arguments|
        boot_workers

        data = Marshal.dump(arguments)
        @input_write.write(data)
        @input_write.flush

        reap_workers
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
        # TODO setup signal handling
        @input_write.close
        $stdin.reopen(@input_read)
        $stdin.sync = true
        @script.after_fork(worker)

        while arguments = Marshal.load($stdin)
          @script.perform(*arguments)
        end
      end

      worker
    end

    def reap_workers
      workers.select { |worker| worker.reap }
    end
  end
end
