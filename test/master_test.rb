require File.expand_path("../setup", __FILE__)
require "divvy"

# Tests that make sure the example.rb file runs and generates tickets.
class MasterTest < MiniTest::Unit::TestCase
  class SimpleTask
    include Divvy::Parallelizable

    def dispatch
      10.times(&block)
    end

    def process(num)
    end
  end

  def setup
    @task = SimpleTask.new
    @master = Divvy::Master.new(@task, 2)
  end

  def teardown
    @master.shutdown!
  end

  def test_worker_object_instantiation
    assert_equal 2, @master.workers.size

    assert_equal 1, @master.workers[0].number
    assert_equal 2, @master.workers[1].number

    @master.workers.each { |worker| assert_nil worker.pid }
    @master.workers.each { |worker| assert_nil worker.status }
  end

  def test_workers_running_check
    assert !@master.workers_running?
  end

  def test_master_process_check
    assert @master.master_process?
    assert !@master.worker_process?
  end

  def test_start_server
    @master.start_server
    assert File.exist?(@master.socket)
  end

  def test_boot_workers
    @master.start_server
    @master.boot_workers
    assert @master.workers_running?
    assert @master.workers.all? { |w| w.running? }
  end

  def test_reaping_and_killing_workers
    @master.start_server
    @master.boot_workers
    reaped = @master.reap_workers
    assert_equal 0, reaped.size

    @master.kill_workers("KILL")
    sleep 0.100
    reaped = @master.reap_workers
    assert_equal 2, reaped.size
  end

  def test_installing_and_uninstalling_signal_traps
    traps = @master.install_signal_traps
    assert traps.is_a?(Array)
    assert traps.size >= 4

    @master.reset_signal_traps
    assert_equal 0, traps.size
  end

  class SuccessfulTask
    include Divvy::Parallelizable

    def dispatch
      yield 'just one thing'
    end

    def process(arg)
      if arg != 'just one thing'
        fail "expected arg to be 'just one thing'"
      end
    end
  end

  def test_successful_run
    task = SuccessfulTask.new
    master = Divvy::Master.new(task, 1)
    master.run
  end

  class StatsTask
    include Divvy::Parallelizable

    def dispatch(&block)
      10.times(&block)
    end

    def process(num)
      if num % 2 == 0
        fail "simulated failure"
      else
        true
      end
    end

    def after_fork(worker)
      $stderr.reopen("/dev/null")
    end
  end

  def test_stats
    task = StatsTask.new
    master = Divvy::Master.new(task, 5)
    master.run
    assert_equal 5, master.failures
    assert_equal 10, master.tasks_distributed
  end

  class FlappingWorkerTask
    include Divvy::Parallelizable

    def dispatch
      yield 'never makes it'
    end

    def after_fork(worker)
      exit! 1
    end
  end

  def test_flapping_worker_detection
    task = FlappingWorkerTask.new
    master = Divvy::Master.new(task, 1)
    assert_raises(Divvy::Master::BootFailure) do
      master.run
    end
    assert_equal 1, master.failures
  end
end
