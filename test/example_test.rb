require File.expand_path("../setup", __FILE__)
require "divvy"

# Tests that make sure the example.rb file runs and generates tickets.
class ExampleTest < MiniTest::Unit::TestCase
  def test_running_the_example_program
    example_script = File.expand_path("../../example.rb", __FILE__)
    output = `divvy -n 2 '#{example_script}'`
    assert $?.success?, "example program should exit successfully"
    assert_equal 11, output.split("\n").size
  end
end
