unless ENV['RAILS_ENV'] == 'test'
  begin
    require 'daemons'
  rescue LoadError
    raise "You need to add gem 'daemons' to your Gemfile if you wish to use it."
  end
end
require 'fileutils'
require 'optparse'
require 'pathname'
require 'parallel'

module ParallelDelayed
  class Command # rubocop:disable ClassLength
    attr_accessor :worker_count, :worker_pools

    DIR_PWD = Pathname.new Dir.pwd

    def initialize(args) # rubocop:disable MethodLength
      @options = {
        :quiet => true,
        :pid_dir => "#{root}/tmp/pids",
        :log_dir => "#{root}/log"
      }

      @worker_count = 1
      @monitor = false

      opts = OptionParser.new do |opt|
        opt.banner = "Usage: #{File.basename($PROGRAM_NAME)} [options] start|stop"

        opt.on('-h', '--help', 'Show this message') do
          puts opt
          exit 1
        end
        opt.on('-e', '--environment=NAME', 'Specifies the environment to run this delayed jobs under (test/development/production).') do |_e|
          STDERR.puts 'The -e/--environment option has been deprecated and has no effect. Use RAILS_ENV and see http://github.com/collectiveidea/delayed_job/issues/7'
        end
        opt.on('--min-priority N', 'Minimum priority of jobs to run.') do |n|
          @options[:min_priority] = n
        end
        opt.on('--max-priority N', 'Maximum priority of jobs to run.') do |n|
          @options[:max_priority] = n
        end
        opt.on('-n', '--number_of_workers=workers', 'Number of unique workers to spawn') do |worker_count|
          @worker_count = worker_count.to_i rescue 1
        end
        opt.on('--pid-dir=DIR', 'Specifies an alternate directory in which to store the process ids.') do |dir|
          @options[:pid_dir] = dir
        end
        opt.on('--log-dir=DIR', 'Specifies an alternate directory in which to store the delayed_job log.') do |dir|
          @options[:log_dir] = dir
        end
        opt.on('-i', '--identifier=n', 'A numeric identifier for the worker.') do |n|
          @options[:identifier] = n
        end
        opt.on('-m', '--monitor', 'Start monitor process.') do
          @monitor = true
        end
        opt.on('--max-memory N', 'Maximum amount of memory to allocate.') do |n|
          @options[:max_memory] = n.to_i
        end
        opt.on('--sleep-delay N', 'Amount of time to sleep when no jobs are found') do |n|
          @options[:sleep_delay] = n.to_i
        end
        opt.on('--read-ahead N', 'Number of jobs from the queue to consider') do |n|
          @options[:read_ahead] = n
        end
        opt.on('-p', '--prefix NAME', 'String to be prefixed to worker process names') do |prefix|
          @options[:prefix] = prefix
        end
        opt.on('--queues=queues', 'Specify which queue DJ must look up for jobs') do |queues|
          @options[:queues] = queues.split(',')
        end
        opt.on('--queue=queue', 'Specify which queue DJ must look up for jobs') do |queue|
          @options[:queues] = queue.split(',')
        end
        opt.on('--pool=queue1[,queue2][:worker_count]', 'Specify queues and number of workers for a worker pool') do |pool|
          parse_worker_pool(pool)
        end
        opt.on('--exit-on-complete', 'Exit when no more jobs are available to run. This will exit if all jobs are scheduled to run in the future.') do
          @options[:exit_on_complete] = true
        end
        opt.on('--daemon-options a, b, c', Array, 'options to be passed through to daemons gem') do |daemon_options|
          @daemon_options = daemon_options
        end
      end
      @args = opts.parse!(args) + (@daemon_options || [])
    end

    def daemonize # rubocop:disable PerceivedComplexity
      dir = @options[:pid_dir]
      FileUtils.mkdir_p(dir) unless File.exist?(dir)

      if worker_pools
        setup_pools
      elsif @options[:identifier]
        # rubocop:disable GuardClause
        if worker_count > 1
          raise ArgumentError, 'Cannot specify both --number-of-workers and --identifier'
        else
          run_process("delayed_job.#{@options[:identifier]}", @options)
        end
        # rubocop:enable GuardClause
      else
        worker_count.times do |worker_index|
          process_name = worker_count == 1 ? 'delayed_job' : "delayed_job.#{worker_index}"
          run_process(process_name, @options)
        end
      end
    end

    def setup_pools
      worker_index = 0
      @worker_pools.each do |queues, worker_count|
        options = @options.merge(:queues => queues)
        worker_count.times do
          process_name = "delayed_job.#{worker_index}"
          run_process(process_name, options)
          worker_index += 1
        end
      end
    end

    def run_process(process_name, options = {})
      if @args.include?('stop')
        `touch #{options[:pid_dir]}/stop_delayed_jobs#{"_#{process_name}" if process_name.match('.')}`
      else
        File.delete("#{options[:pid_dir]}/stop_delayed_jobs") if File.exists?("#{options[:pid_dir]}/stop_delayed_jobs")
        Delayed::Worker.before_fork
        Daemons.run_proc(process_name, :dir => options[:pid_dir], :dir_mode => :normal, :monitor => @monitor, :ARGV => @args) do |*_args|
          $0 = File.join(options[:prefix], process_name) if @options[:prefix]
          run process_name, options
        end
      end
    end

    def run(worker_name = nil, options = {})
      pid_file = "#{options[:pid_dir]}/#{worker_name}.parallel.pid"
      File.open(pid_file, 'w'){|f| f.write(Process.pid)} # create PID file
      Dir.chdir(root)

      Delayed::Worker.after_fork
      Delayed::Worker.logger ||= Logger.new(File.join(@options[:log_dir], 'delayed_job.log'))
      cycles_ran = 0

      while true
        break if File.exists?("#{options[:pid_dir]}/stop_delayed_jobs") || File.exists?("#{options[:pid_dir]}/stop_delayed_jobs_#{worker_name}")
        no_job_res = Parallel.map([[worker_name, options]], :in_processes => 1) do |process_name, worker_options|
          no_jobs = nil
          while true
            break if no_jobs && worker_options[:exit_on_complete]
            break if File.exists?("#{worker_options[:pid_dir]}/stop_delayed_jobs") || File.exists?("#{worker_options[:pid_dir]}/stop_delayed_jobs_#{process_name}")
            if worker_options[:max_memory].to_i > 0
              pid, size = `ps ax -o pid,rss | grep -E "^[[:space:]]*#{Process.pid}"`.strip.split.map(&:to_i)
              break if size > worker_options[:max_memory]
            end
            jobs_res = Delayed::Worker.new(worker_options).work_off(worker_options[:read_ahead] || 1)
            no_jobs = !jobs_res || (jobs_res.sum == 0)
            sleep(options[:sleep_delay]) if no_jobs && worker_options[:sleep_delay]
          end
          no_jobs
        end
        GC.start if (cycles_ran += 1) % 100 == 0
        break if no_job_res.first && options[:exit_on_complete]
        if options[:max_memory].to_i > 0
          pid, size = `ps ax -o pid,rss | grep -E "^[[:space:]]*#{Process.pid}"`.strip.split.map(&:to_i)
          break if size > options[:max_memory]
        end
        sleep(options[:sleep_delay]) if no_job_res.first && options[:sleep_delay]
      end
      File.delete(pid_file) if File.exists?(pid_file) # delete PID file
    rescue => e
      STDERR.puts e.message
      STDERR.puts e.backtrace
      ::Rails.logger.fatal(e) if rails_logger_defined?
      File.delete(pid_file) if File.exists?(pid_file) # delete PID file
      exit_with_error_status
    end

  private

    def parse_worker_pool(pool)
      @worker_pools ||= []

      queues, worker_count = pool.split(':')
      queues = ['*', '', nil].include?(queues) ? [] : queues.split(',')
      worker_count = (worker_count || 1).to_i rescue 1
      @worker_pools << [queues, worker_count]
    end

    def root
      @root ||= rails_root_defined? ? ::Rails.root : DIR_PWD
    end

    def rails_root_defined?
      defined?(::Rails.root)
    end

    def rails_logger_defined?
      defined?(::Rails.logger)
    end

    def exit_with_error_status
      exit 1
    end
  end
end
