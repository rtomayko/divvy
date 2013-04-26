require 'divvy/parallelizable'
require 'divvy/master'
require 'divvy/worker'

module Divvy
  # Load a script that defines a Divvy::Parallelizable object. A class that
  # includes the Parallelizable module must be defined in order for this to work.
  #
  # file - Script file to load.
  #
  # Returns an object that implements the Parallelizable interface.
  # Raises a RuntimeError when no parallelizable object was defined.
  def self.load(file)
    Kernel::load(file)

    if subclass = Parallelizable.parallelizable.last
      @receiver = subclass.new
    else
      fail "#{file} does not define a Divvy::Parallelizable object"
    end
  end
end
