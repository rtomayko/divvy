divvy - parallel script runner
=============================

This is a (forking) parallel task runner for Ruby designed to be run in the
foreground (i.e. not a server) with minimum infrastucture components (like redis
or a queue server).

Example
-------

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

class NumbersToSHA1 < Divvy::Script
  # This is the main loop responsible for generating work items for worker
  # processes. It runs in the master process only. Each item yielded from this
  # method is marshalled over a pipe and distributed to the next available
  # worker process where it arrives at the #perform method (see below).
  def dispatch
    count = ARGV[0] ? ARGV[0].to_i : 1_000
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
