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

    def self.load(file)
      
    end
  end
end
