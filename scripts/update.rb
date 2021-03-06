#!/usr/bin/ruby

require File.expand_path("../../lib/config", __FILE__)
require 'rota/model'
require 'rota/fetcher'
require 'rota/updater'

include Rota

# start workers
$workers = []
Rota::Config['updater']['threads']['default'].times do
  w = TaskWorker.new
  $workers << w
  w.run
end

at_exit do
  $workers.each do |w|
    w.send([:done])
    w.wait
  end
end

Rota.setup_and_finalize

def log(msg)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M')}] #{msg}"
end

def help_text
  puts <<END
Usage: scripts/update [-p|--progress] [[-s|--semester] id] target1 target2 ...

Available targets:
  * timetables
  * profiles
  * programs
  * buildings
END
end

if ARGV.size == 0
  help_text()
  Kernel.exit(1)
end

log "Updating semester list..."
UpdateTasks::SemesterListTask.new.run

t = TaskRunner.new(Semester.all.collect { |s| UpdateTasks::SemesterTask.new(s) }, $workers)
t.run("Update semester details")

log "Updating campus list..."
UpdateTasks::CampusListTask.new.run

mode = []
target_semester = Semester.current
terminal = false

while (arg = ARGV.shift)
  if arg == '--semester' or arg == '-s'
    semid = ARGV.shift
    if semid == 'list' or semid == 'help'
      Semester.all.each do |sem|
        puts "#{sem['id']} / #{sem.name}"
      end
      Kernel.exit()
    end
    if semid.downcase == "current"
      semid = :current
    else
      semid = semid.to_i
      target_semester = Semester.get(semid)
    end
  elsif arg == '--progress' or arg == '-p'
    terminal = true
  elsif arg == 'timetables'
    mode << :courses
    mode << :timetables
  elsif arg == 'profiles'
    mode << :courses
    mode << :profiles
  elsif arg == 'programs'
    mode << :programs
  elsif arg == 'buildings'
    mode << :buildings
  else
    help_text()
    Kernel.exit(1)
  end
end

if mode.size == 0
  log "Nothing to do..."
end

if mode.include? :buildings
  log "Updating building index..."
  UpdateTasks::BuildingListTask.new.run
end

if mode.include? :programs
  log "Updating undergraduate program list..."
  UpdateTasks::ProgramListTask.new.run
  
  programs = Program.all
  tasks = programs.collect { |p| UpdateTasks::ProgramTask.new(p) }
  t = TaskRunner.new(tasks, $workers)
  t.run("All Programs update", terminal)
end

if mode.include? :courses
  log "Updating supplementary course index..."
  UpdateTasks::CourseListTask.new.run
end

if mode.include? :profiles
  courses = Course.all
  tasks = courses.collect { |c| UpdateTasks::CourseTask.new(c) }
  t = TaskRunner.new(tasks, $workers)
  t.run("All Course information update", terminal)
end

if mode.include? :timetables
  offerings = Offering.all(:semester => target_semester)
  tasks = offerings.collect { |o| UpdateTasks::TimetableTask.new(o) }
  
  t = TaskRunner.new(tasks, $workers)
  t.run("Timetable update for #{target_semester['id']}/#{target_semester.name}", terminal)
end

if mode.include? :profiles
  tasks = []
  Course.all.each do |c|
    pp = c.offerings.select { |o| o.current and o.profile_id > 0 }.first
    if pp.nil?
      pp = c.offerings.select { |o| o.profile_id > 0 }.first
    end
    tasks << UpdateTasks::ProfileTask.new(pp) unless pp.nil?
  end
  t = TaskRunner.new(tasks, $workers)
  t.run("Current course profiles update", terminal)
end
