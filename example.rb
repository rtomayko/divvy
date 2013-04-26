# This is a dance party. We're going to hand out tickets. We need to generate
# codes for each available ticket. Thing is, the ticket codes have to be
# generated by this external ticket code generator service (this part is
# just pretend) and there's a lot of latency involved. We can generate multiple
# ticket codes at the same time by making multiple connections.
require 'divvy'
require 'digest/sha1' # <-- your humble ticket code generator service

class DanceParty
  # The Parallelizable module provides default method implementations and marks
  # the object as following the interface defined below.
  include Divvy::Parallelizable

  # This is the main loop responsible for generating work items for worker
  # processes. It runs in the master process only. Each item yielded from this
  # method is marshalled over a pipe and distributed to the next available
  # worker process where it arrives at the #perform method (see below).
  #
  # In this example we're just going to generate a series of numbers to pass
  # to the workers. The workers just write the number out with their pid and the
  # SHA1 hex digest of the number given.
  def dispatch
    tickets_available = ARGV[0] ? ARGV[0].to_i : 10
    puts "Generating #{tickets_available} ticket codes for the show..."
    (0...tickets_available).each do |ticket_number|
      yield ticket_number
    end
  end

  # The individual work item processing method. Each item produced by the
  # dispatch method is sent to this method in the worker processes. The
  # arguments to this method must match the arity of the work item yielded
  # from the #dispatch method.
  #
  # In this example we're given a Fixnum ticket number and asked to produce a
  # code. Pretend this is a network intense operation where you're mostly
  # sleeping waiting for a reply.
  def perform(ticket_number)
    ticket_sha1 = Digest::SHA1.hexdigest(ticket_number.to_s)
    printf "%5d %6d %s\n" % [$$, ticket_number, ticket_sha1]
    sleep 0.150 # fake some latency
  end

  # Hook called after a worker process is forked off from the master process.
  # This runs in the worker process only. Typically used to re-establish
  # connections to external services or open files (logs and such).
  def after_fork(worker)
    # warn "In after_fork for worker #{worker.number}"
  end

  # Hook called before a worker process is forked off from the master process.
  # This runs in the master process only. This can be used to monitor the rate
  # at which workers are being created or to set a starting process state for
  # the newly forked process.
  def before_fork(worker)
    # warn "In before_fork for worker #{worker.number}"
  end
end
