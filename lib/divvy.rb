require 'divvy/parallelizable'
require 'divvy/master'
require 'divvy/worker'

module Divvy
  def self.load(file)
    Kernel::load(file)

    if subclass = Parallelizable.parallelizable.last
      @receiver = subclass.new
    else
      fail "#{file} does not define a Divvy::Parallelizable object"
    end
  end
end
