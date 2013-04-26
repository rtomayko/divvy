# Basic test environment.
#
# This should set up the load path for testing only. Don't require any support libs
# or gitrpc stuff in here.

# bring in minitest
require 'minitest/autorun'

# add bin dir to path for testing command
ENV['PATH'] = [
  File.expand_path("../../bin", __FILE__),
  ENV['PATH']
].join(":")

# put lib dir directly to load path
$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

# child processes inherit our load path
ENV['RUBYLIB'] = $LOAD_PATH.join(":")
