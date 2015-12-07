# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rbvppc/version'

Gem::Specification.new do |spec|
  spec.name          = "rbvppc"
  spec.version       = Rbvppc::VERSION
  spec.authors       = ["John F. Hutchinson, Chris Wood"]
  spec.email         = ["jfhutchi@us.ibm.com, woodc@us.ibm.com"]
  spec.summary       = %q{Remote access library for IBM P-Series}
  spec.description   = %q{This gem provides remote access to IBM P-Series}
  spec.homepage      = "https://github.com/pseries/rbvppc"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency('net-ssh', "~> 2.8")

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake", "~> 0"
  spec.required_ruby_version = '>= 2.1.0'
end
