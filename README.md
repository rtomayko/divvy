divvy - parallel script runner
=============================

This is a (forking) parallel task runner for Ruby designed to be run in the
foreground (i.e. not a server) with minimum infrastucture components (like redis
or a queue server).

## example

This is a simple and contrived example of a job script. The only requirements
are that you subclass `Divvy::Script` and implement the `#dispatch` and
`#perform` methods. There are also hooks available for tapping into the worker
process lifecycle.

The example generates tasks for a series of numbers. The task items are routed
to an available worker process where they're SHA1 hexdigest is calculated and
written to standard output.

``` ruby
require 'digest/sha1'
require 'divvy'

class NumbersToSHA1
  # The Parallelizable module provides default method implementations and marks
  # the object as following the interface defined below.
  include Divvy::Parallelizable

  # This is the main loop responsible for generating work items for worker
  # processes. It runs in the master process only. Each item yielded from this
  # method is marshalled over a pipe and distributed to the next available
  # worker process where it arrives at the #perform method (see below).
  def dispatch
    count = ARGV[0] ? ARGV[0].to_i : 10
    (0...count).each { |num| yield num }
  end

  # The individual work item processing method. Each item produced by the
  # dispatch method is sent to this method in the worker processes. The
  # arguments to this method must match the arity of the work item yielded
  # from the #dispatch method.
  def perform(num)
    printf "%5d %8d %s\n" % [$$, num, Digest::SHA1.hexdigest(num.to_s)]
  end

  # Hook called after a worker process is forked off from the master process.
  # This runs in the worker process only. Typically used to re-establish
  # connections to external services or open files (logs and such).
  #
  # worker - A Divvy::Worker object describing the process that was just
  #          created. Always the current process ($$).
  #
  # Returns nothing.
  def after_fork(worker)
    # warn "In after_fork for worker #{worker.number}"
  end

  # Hook called before a worker process is forked off from the master process.
  # This runs in the master process only.
  #
  # worker - Divvy::Worker object descibing the process that's about to fork.
  #          Worker#pid will be nil but Worker#number (1..worker_count) is
  #          always available.
  #
  # Returns nothing.
  def before_fork(worker)
    # warn "In before_fork for worker #{worker.number}"
  end
end
```

### divvy command

You can run the example script above with the `divvy` command, which includes
options for controlling concurrency and other cool stuff. Here we use five
worker processes:

```
$ divvy -n 5 example.rb
51589        0 b6589fc6ab0dc82cf12099d1c2d40ab994e8410c
51590        1 356a192b7913b04c54574d18c28d46e6395428ab
51589        4 1b6453892473a467d07372d45eb05abc2031647a
51590        5 ac3478d69a3c81fa62e60f5c3696165a4e5e6ac4
51591        2 da4b9237bacccdf19c0760cab7aec4a8359010b0
51589        6 c1dfd96eea8cc2b62785275bca38ac261256e278
51592        3 77de68daecd823babbb58edb1c8e14d7106e83bb
51590        8 fe5dbbcea5ce7e2988b8c69bcfdfde8904aabc1f
51591        9 0ade7c2cf97f75d009975f4d720d1fa6c19f4897
51593        7 902ba3cda1883801594b6e1b452790cc53948fda
```

The columns of output are the worker pid, number argument, and the SHA1 hex
digest of the number. You can see items are distributed between workers may not
be processed in order.

### manual runner

You can also turn the current process into a divvy master process by creating a
`Divvy::Master` object, passing an instance of `Parallelizable`

``` ruby
task = NumbersToSHA1.new
master = Divvy::Master.new(task, 10)
master.run
```
