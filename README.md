# ParallelDelayed

Utilize parallel with delayed_job to kill processes and keep mem usage low. After every work_off, we kill the process, free memory, and start a fresh process

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'parallel_delayed'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install parallel_delayed

## Usage

In your rails application's script/delayed_job or bin/delayed_job, replace `Delayed::Command` with `ParallelDelayed::Command`

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/joeheald85/parallel_delayed.
