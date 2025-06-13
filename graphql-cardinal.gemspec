# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'graphql/cardinal/version'

Gem::Specification.new do |spec|
  spec.name          = 'graphql-cardinal'
  spec.version       = GraphQL::Cardinal::VERSION
  spec.authors       = ['Greg MacWilliam']
  spec.summary       = 'A breadth-first executor for GraphQL Ruby'
  spec.description   = 'A breadth-first executor for GraphQL Ruby'
  spec.homepage      = 'https://github.com/gmac/graphql-cardinal-ruby'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata    = {
    'homepage_uri' => 'https://github.com/gmac/graphql-cardinal-ruby',
    'changelog_uri' => 'https://github.com/gmac/graphql-cardinal-ruby/releases',
    'source_code_uri' => 'https://github.com/gmac/graphql-cardinal-ruby',
    'bug_tracker_uri' => 'https://github.com/gmac/graphql-cardinal-ruby/issues',
  }

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^test/})
  end
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'graphql', '>= 2.0'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 12.0'
  spec.add_development_dependency 'minitest', '~> 5.12'
end
