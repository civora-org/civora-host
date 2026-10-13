# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Decidim's factories draw organization names from Faker's unique generator,
    # which holds a finite list; a growing suite exhausts it within one process
    # (Faker::UniqueGenerator::RetryLimitExceeded). Reset it for every test.
    setup { Faker::UniqueGenerator.clear if defined?(Faker::UniqueGenerator) }

    # Add more helper methods to be used by all tests here...
  end
end
