module Divvy
  # Module defining the main task interface. Parallelizable classes must respond
  # to #dispatch and #perform and may override hook methods to tap into the
  # worker process lifecycle.
  module Parallelizable
    # The main loop responsible for generating task items to process in workers.
    # Runs in the master process only. Each item this method yields is distributed
    # to one of a pool of worker processes where #perform (see below) is invoked
    # to process the task item.
    #
    # The arguments yielded to the block are passed with same arity to
    # the #perform method. Only marshallable types may be included.
    #
    # The dispatch method takes no arguments. It's expected that the receiving
    # object is setup with all necessary state to generate task items or can
    # retrieve the information it needs from elsewhere.
    #
    # When the dispatch method returns the master process exits.
    # If an exception is raised, the program exits non-zero.
    def dispatch
      raise NotImplementedError, "#{self.class} must implement #dispatch method"
    end

    # Process an individual task item. Each item produced by #dispatch is sent here
    # in one of a pool of the worker processes. The arguments to this method must
    # match the arity of the task item yielded from #dispatch.
    def perform(*args)
      raise NotImplementedError, "#{self.class} must implement perform method"
    end

    # Hook called after a worker process is forked off from the master process.
    # This runs in the worker process only. Typically used to re-establish
    # connections to external services or open files (logs and such).
    #
    # worker - A Divvy::Worker object describing the process that was just
    #          created. Always the current process ($$).
    #
    # Return value is ignored.
    def after_fork(worker)
    end

    # Hook called before a worker process is forked off from the master process.
    # This runs in the master process only.
    #
    # worker - Divvy::Worker object descibing the process that's about to fork.
    #          Worker#pid will be nil but Worker#number (1..worker_count) is
    #          always available.
    #
    # Return value is ignored.
    def before_fork(worker)
    end

    # Track classes and modules that include this module.
    @parallelizable = []
    def self.included(mod)
      @parallelizable << mod if self == Divvy::Parallelizable
      super
    end
    def self.parallelizable; @parallelizable; end
  end
end
