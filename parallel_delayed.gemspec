
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "parallel_delayed/version"

Gem::Specification.new do |spec|
  spec.name          = "parallel_delayed"
  spec.version       = ParallelDelayed::VERSION
  spec.authors       = ["Joe Heald"]
  spec.email         = ["joeheald85@gmail.com"]

  spec.summary       = %q{Utilize parallel with delayed_job to kill processes and keep mem usage low.}
  spec.description   = %q{Utilize parallel with delayed_job to kill processes and keep mem usage low. After every job, we kill the process, free memory, and start a fresh process}
  spec.homepage      = "https://github.com/joeheald85/parallel_delayed"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "https://github.com/"

    spec.metadata["homepage_uri"] = spec.homepage
    spec.metadata["source_code_uri"] = "https://github.com/joeheald85/parallel_delayed"
    spec.metadata["changelog_uri"] = "https://github.com/joeheald85/parallel_delayed"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.17"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_dependency "delayed_job"
  spec.add_dependency "parallel"
end
