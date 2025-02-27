# frozen_string_literal: true

desc('List configured BigBlueButton servers')
task servers: :environment do
  servers = Server.all
  puts('No servers are configured') if servers.empty?
  servers.each do |server|
    puts("id: #{server.id}")
    puts("\turl: #{server.url}")
    puts("\tsecret: #{server.secret}")
    if server.state.present?
      puts("\t#{server.state}")
    else
      puts("\t#{server.enabled ? 'enabled' : 'disabled'}")
    end
    puts("\tload: #{server.load.presence || 'unavailable'}")
    puts("\tload multiplier: #{server.load_multiplier.nil? ? 1.0 : server.load_multiplier.to_d}")
    puts("\t#{server.online ? 'online' : 'offline'}")
  end
end

namespace :servers do
  desc 'Add a new BigBlueButton server (it will be added disabled)'
  task :add, [:url, :secret, :load_multiplier] => :environment do |_t, args|
    if args.url.nil? || args.secret.nil?
      puts('Error: Please input at least a URL and a secret!')
      exit(1)
    end
    tmp_load_multiplier = 1.0
    unless args.load_multiplier.nil?
      tmp_load_multiplier = args.load_multiplier.to_d
      if tmp_load_multiplier.zero?
        puts('WARNING! Load-multiplier was not readable or 0, so it is now 1')
        tmp_load_multiplier = 1.0
      end
    end
    server = Server.create!(url: args.url, secret: args.secret, load_multiplier: tmp_load_multiplier)
    puts('OK')
    puts("id: #{server.id}")
  end

  desc 'Update a BigBlueButton server'
  task :update, [:id, :secret, :load_multiplier] => :environment do |_t, args|
    server = Server.find(args.id)
    server.secret = args.secret unless args.secret.nil?
    tmp_load_multiplier = server.load_multiplier
    unless args.load_multiplier.nil?
      tmp_load_multiplier = args.load_multiplier.to_d
      if tmp_load_multiplier.zero?
        puts('WARNING! Load-multiplier was not readable or 0, so it is now 1')
        tmp_load_multiplier = 1.0
      end
    end
    server.load_multiplier = tmp_load_multiplier
    server.save!
    puts('OK')
  rescue ApplicationRedisRecord::RecordNotFound
    puts("ERROR: No server found with id: #{args.id}")
  end

  desc 'Remove a BigBlueButton server'
  task :remove, [:id] => :environment do |_t, args|
    server = Server.find(args.id)
    server.destroy!
    puts('OK')
  rescue ApplicationRedisRecord::RecordNotFound
    puts("ERROR: No server found with id: #{args.id}")
  end

  desc 'Mark a BigBlueButton server as available for scheduling new meetings'
  task :enable, [:id] => :environment do |_t, args|
    server = Server.find(args.id)
    server.state = 'enabled'
    server.save!
    puts('OK')
  rescue ApplicationRedisRecord::RecordNotFound
    puts("ERROR: No server found with id: #{args.id}")
  end

  desc 'Mark a BigBlueButton server as cordoned to stop scheduling new meetings but consider for
        load calculation and joining existing meetings'
  task :cordon, [:id] => :environment do |_t, args|
    server = Server.find(args.id)
    server.state = 'cordoned'
    server.save!
    puts('OK')
  rescue ApplicationRedisRecord::RecordNotFound
    puts("ERROR: No server found with id: #{args.id}")
  end

  desc 'Mark a BigBlueButton server as unavailable to stop scheduling new meetings'
  task :disable, [:id] => :environment do |_t, args|
    include ApiHelper
    server = Server.find(args.id)
    response = true
    if server.load.to_f > 0.0
      puts("WARNING: You are trying to disable a server with active load. You should use the cordon option if
          you do not want to clear all the meetings")
      puts('If you still wish to continue please enter `yes`')
      response = $stdin.gets.chomp.casecmp('yes').zero?
      if response
        meetings = Meeting.all.select { |m| m.server_id == server.id }
        meetings.each do |meeting|
          puts("Clearing Meeting id=#{meeting.id}")
          moderator_pw = meeting.try(:moderator_pw)
          meeting.destroy!
          get_post_req(encode_bbb_uri('end', server.url, server.secret, meetingID: meeting.id, password: moderator_pw))
        rescue ApplicationRedisRecord::RecordNotDestroyed => e
          raise("ERROR: Could not destroy meeting id=#{meeting.id}: #{e}")
        rescue StandardError => e
          puts("WARNING: Could not end meeting id=#{meeting.id}: #{e}")
        end
      end
    end
    server.state = 'disabled' if response
    server.save!
    puts('OK')
  rescue ApplicationRedisRecord::RecordNotFound
    puts("ERROR: No server found with id: #{args.id}")
  end

  desc 'Mark a BigBlueButton server as unavailable, and clear all meetings from it'
  task :panic, [:id, :keep_state] => :environment do |_t, args|
    args.with_defaults(keep_state: false)
    include ApiHelper

    server = Server.find(args.id)

    meetings = Meeting.all.select { |m| m.server_id == server.id }
    meetings.each do |meeting|
      puts("Clearing Meeting id=#{meeting.id}")
      moderator_pw = meeting.try(:moderator_pw)
      meeting.destroy!
      get_post_req(encode_bbb_uri('end', server.url, server.secret, meetingID: meeting.id, password: moderator_pw))
    rescue ApplicationRedisRecord::RecordNotDestroyed => e
      raise("ERROR: Could not destroy meeting id=#{meeting.id}: #{e}")
    rescue StandardError => e
      puts("WARNING: Could not end meeting id=#{meeting.id}: #{e}")
    end
    server.state = 'disabled' unless args.keep_state
    server.save!
    puts('OK')
  rescue ApplicationRedisRecord::RecordNotFound
    puts("ERROR: No server found with id: #{args.id}")
  end

  desc 'Set the load-multiplier of a BigBlueButton server'
  task :loadMultiplier, [:id, :load_multiplier] => :environment do |_t, args|
    server = Server.find(args.id)
    tmp_load_multiplier = 1.0
    unless args.load_multiplier.nil?
      tmp_load_multiplier = args.load_multiplier.to_d
      if tmp_load_multiplier.zero?
        puts('WARNING! Load-multiplier was not readable or 0, so it is now 1')
        tmp_load_multiplier = 1.0
      end
    end
    server.load_multiplier = tmp_load_multiplier
    server.save!
    puts('OK')
  rescue ApplicationRedisRecord::RecordNotFound
    puts("ERROR: No server found with id: #{args.id}")
  end

  desc 'Adds multiple BigBlueButton servers defined in a YAML file passed as an argument'
  task :addAll, [:path] => :environment do |_t, args|
    servers = YAML.load_file(args.path)['servers']
    servers.each do |server|
      created = Server.create!(url: server['url'], secret: server['secret'])
      puts("server: #{created.url}")
      puts("id: #{created.id}")
    end
  rescue StandardError => e
    puts(e)
  end

  desc 'Sync cluster state with servers defined in a YAML file'
  task :sync, [:path, :mode, :dryrun] => :environment do |_t, args|
    raise "Missing 'path' parameter" if args.path.blank?
    args.with_defaults(mode: 'cordon', dryrun: false)

    ServerSync.sync_file(args.path, args.mode, args.dryrun)
  rescue StandardError => e
    puts("ERROR: #{e}")
    exit(1)
  end

  desc 'Return a yaml compatible with servers:sync'
  task :yaml, [:verbose] => :environment do |_t, args|
    puts({ servers: ServerSync.dump(!!args.verbose) }.to_yaml)
  end

  desc('List all meetings running in specific BigBlueButton servers')
  task :meeting_list, [:server_ids] => :environment do |_t, args|
    include ApiHelper

    args.with_defaults(server_ids: '')
    server_ids = args.server_ids.split(':')
    servers = if server_ids.present?
                server_ids.map { |id| Server.find(id) }
              else
                Server.all
              end
    pool = Concurrent::FixedThreadPool.new(Rails.configuration.x.poller_threads.to_i - 1, name: 'sync-meeting-data')
    tasks = servers.map do |server|
      Concurrent::Promises.future_on(pool) do
        puts("\nServer ID: #{server.id}")
        puts("Server Url: #{server.url}")
        resp = get_post_req(encode_bbb_uri('getMeetings', server.url, server.secret))
        meetings = resp.xpath('/response/meetings/meeting')
        meeting_ids = meetings.map { |meeting| meeting.xpath('.//meetingName').text }
        puts("MeetingIDs: \n\t#{meeting_ids.join("\n\t")}")
        puts("\tNo meetings to display") if meeting_ids.empty?
      rescue BBBErrors::BBBError => e
        puts("\nFailed to get server id=#{server.id} status: #{e}")
      rescue StandardError => e
        puts("\nFailed to get meetings list status: #{e}")
      end
    end
    begin
      Concurrent::Promises.zip_futures_on(pool, *tasks).wait!(Rails.configuration.x.poller_wait_timeout)
    rescue StandardError => e
      Rails.logger.warn("Error #{e}")
    end

    pool.shutdown
    pool.wait_for_termination(5) || pool.kill
  end
end
