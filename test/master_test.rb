require File.expand_path("../setup", __FILE__)
require "divvy"

# Tests that make sure the example.rb file runs and generates tickets.
class MasterTest < MiniTest::Unit::TestCase
  class SuccessfulTask
    include Divvy::Parallelizable

    def dispatch
      yield 'just one thing'
    end

    def perform(arg)
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

    def perform(num)
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
