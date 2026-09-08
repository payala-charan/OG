# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

# Example:
#
# set :output, "/path/to/my/cron_log.log"
#
# every 2.hours do
#   command "/usr/bin/some_great_command"
#   runner "MyModel.some_method"
#   rake "some:great:rake:task"
# end
#
# every 4.days do
#   runner "AnotherModel.prune_old_records"
# end

# Learn more: http://github.com/javan/whenever
# every 1.day, at: '9:00 am' do
#   runner "AutoValidationProcess.new.call"
# end

env :PATH, "/Users/vigneshgorakala/.rbenv/shims:/Users/vigneshgorakala/.rbenv/bin:/usr/bin:/bin"
set :environment, "development"
set :output, "log/cron.log"

# every 2.minutes do
#   command "cd /Users/vigneshgorakala/projects/excel && /Users/vigneshgorakala/.rbenv/shims/bundle exec rails runner -e development 'AutoValidationRunner.call' >> log/cron.log 2>&1"
# end
every 1.day, at: [ "9:00 am", "9:00 pm" ] do
  command "cd /Users/vigneshgorakala/projects/excel && /Users/vigneshgorakala/.rbenv/shims/bundle exec rails runner -e development 'AutoValidationRunner.call' >> log/cron.log 2>&1"
end