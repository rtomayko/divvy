module Trans
  class Script
    def dispatch
      $stdin.each_line { |line| yield line }
    end

    def perform(*args)
      raise NotImplementedError
    end

    def before_fork
    end

    def after_fork
    end

    # The unix domain socket file used to communicate between master and worker
    def socket
      @socket ||= "/tmp/trans-#{$$}.sock"
    end

    def self.load(file)
      Kernel::load(file)

      if subclass = @subclasses.last
        subclass.new
      else
        fail "#{file} does not define a subclass of Trans::Script"
      end
    end

    @subclasses = []
    def self.inherited(subclass)
      @subclasses << subclass if self == Trans::Script
      super
    end
  end
end
