# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name        = "divvy"
  s.version     = "1.1"
  s.platform    = Gem::Platform::RUBY
  s.authors     = %w[@rtomayko]
  s.email       = ["rtomayko@gmail.com"]
  s.homepage    = "https://github.com/rtomayko/divvy"
  s.description = "little ruby parallel script runner"
  s.summary     = "..."

  s.add_development_dependency "rake"
  s.add_development_dependency "minitest"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- test`.split("\n").select { |f| f =~ /_test.rb$/ }
  s.executables   = `git ls-files -- bin`.split("\n").map { |f| File.basename(f) }
  s.require_paths = %w[lib]
end
