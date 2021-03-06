#!/usr/bin/ruby

require File.expand_path('../lib/config', __FILE__)

require 'rota/model'
require 'rota/metamodel'

require 'nokogiri'
require 'bitly'
require 'cinch'
require 'daemons'
require 'net/http'

include Rota::Model

IrcServer = "irc.oftc.net"
IrcNick = "UQbot"
IrcChannels = ["#attic"]

$bitly = Bitly.new("nikosai", 'R_8b9e253948f27fbaf013c9bc6c48a1eb')

module Pastebin
  def Pastebin.paste(code, name, format="text", expire="10M")
    res = Net::HTTP.post_form(URI.parse("http://pastebin.com/api_public.php"),
      {
        'paste_code' => code,
        'paste_name' => name,
        'paste_format' => format,
        'paste_expire_date' => expire
      })
    return res.body
  end
end

bot = Cinch::Bot.new do
  configure do |c|
    c.server = IrcServer
    c.nick = IrcNick
    c.channels = IrcChannels
  end
  
  on :private, /^help$/ do |m|
    m.reply("-- UQbot --")
    m.reply("UQbot can help you find out information about UQ")
    m.reply("All questions and commands can be used in-channel or in private message")
    m.reply("Building information: <help building>")
    m.reply("Course information: <help courses>")
    m.reply("Assessment information: <help assessment>")
  end
  
  on :private, /^help (.+)$/ do |m, topic|
    topic = topic.downcase
    if topic == "building"
      m.reply("-- Building information --")
      m.reply("type 'UQbot: building <searchkey>' to search for a building, either by number or name")
    elsif topic == "courses"
      m.reply("-- Course information --")
      m.reply("type 'UQbot: find <searchkeys>' to search for a course code")
      m.reply("type 'what are prereqs for cour1234?' to display prerequisites for a course")
      m.reply("type 'what plans have cour1234?' to list programs and plans that include a course")
      m.reply("type 'describe cour1234' to get a description of a course")
      m.reply("type 'what depends on cour1234?' to see courses that list COUR1234 as a pre-req")
      m.reply("type 'when is cour1234 offered?' to see a list of semesters when COUR1234 has been offered")
      m.reply("type 'UQbot: link cour1234' to get links to the course summary page and current profile")
    elsif topic == "assessment"
      m.reply("-- Assessment information --")
      m.reply("type 'list assessment for cour1234' to get a list of all assessment items for a course")
      m.reply("type 'when is cour1234 <xyz> due?' to retrieve the due date for an item")
    else
      m.reply("Sorry, I can't find a help topic '#{topic}'")
    end
  end
  
  on :private do |m|
    msg = m.message.downcase
    if msg.include?('peter sutton')
      m.reply("PETER SUTTON IS MY LORD AND MASTER")
    end
  end
  
  on :message do |m|
    msg = m.message.downcase
    codes = msg.scan(/[a-zA-Z]{4}[0-9]{4}/)
    words = msg.split(" ").size
    if (mm = msg.match(/^#{IrcNick.downcase}[:,]? (.+)$/))
      # directed at me!
      msg = mm[1]
      if (mm = msg.match(/^find (.+)$/))
        keys = mm[1].split
        ac = UqCourse.all
        cs = ac.select do |c|
          matches = []
          keys.each do |key|
            ms = []
            ms << (c.code and c.code.downcase.include?(key))
            ms << (c.name and c.name.downcase.include?(key))
            ms << (c.description and c.description.downcase.include?(key))
            matches << ms.include?(true)
          end
          not (matches.include?(false) or matches.include?(nil))
        end
        cs = cs.collect { |c| c.code }
        if (sz=cs.size) > 15
          cs = cs.join("\n")
          url = Pastebin.paste(cs, "UQbot")
          m.reply("#{m.user.nick}: #{sz} courses matching, list at #{url}")
        else
          m.reply("#{m.user.nick}: Matching courses: #{cs.join(', ')}")
        end
        
      elsif (mm = msg.match(/^building (.+)$/))
        keys = mm[1].split
        bs = UqBuilding.all
        bs = bs.select do |b|
          matches = []
          keys.each do |key|
            if b.number.downcase =~ /(^| )#{key}[a-z]*($| )/ or b.name.downcase =~ /(^| )#{key}($| )/
              matches << true
            else
              matches << false
            end
          end
          not (matches.include?(false) or matches.include?(nil))
        end
        bs = bs.collect { |b| 
          link = $bitly.shorten("http://uq.edu.au/maps/index.html?menu=1&id=#{b.map_id}")
          "#{b.name} / #{b.number} (#{link.short_url})"
          }
        if (sz = bs.size) > 5
          bs = bs.join("\n")
          url = Pastebin.paste(bs, "buildings overflow")
          m.reply("#{m.user.nick}: Matching buildings list too long (#{sz}), pasted to #{url}")
        else
          m.reply("#{m.user.nick}: Matching buildings: #{bs.join(', ')}")
        end
        
      elsif (mm = msg.match(/^link (.+)$/))
        codes = mm[1].split
        puts "codes: #{codes.inspect}"
        codes.each do |code|
          puts "course: #{code}"
          cs = UqCourse.get(code)
          if cs
            puts " = #{cs.code}"
            pro = cs.uq_course_profiles.select { |p| p.current }.first
            if (pro.profileId < 0)
              pro = cs.uq_course_profiles.select { |p| p.profileId > 0 }.first
            end

            clink = $bitly.shorten("http://www.uq.edu.au/study/course.html?course_code=#{cs.code}")
            plink = $bitly.shorten("http://www.courses.uq.edu.au/student_section_loader.php?section=print_display&profileId=#{pro.profileId}")
            m.reply("#{m.user.nick}: Course: #{clink.short_url}, Profile for #{pro.semester}: #{plink.short_url}")
          else
            m.reply("#{m.user.nick}: Couldn't find course #{code}?'")
          end
        end
      else
        m.reply("#{m.user.nick}: Nil comprehende, senor?")
      end
      
    elsif words < 10 and codes.size == 1 and not (cs = UqCourse.get(codes[0]))
      m.reply("#{m.user.nick}: You had a course code in that message, #{codes[0]}, that I could not find.")
      
    elsif words < 10 and codes.size == 1 and (cs = UqCourse.get(codes[0]))
      if msg.include?("prereq")
        prs = cs.prereqs.collect { |c| c.prereq.code }.join(", ")
        m.reply("#{m.user.nick}: Prereqs for #{cs.code}: #{prs}")
        
      elsif msg.include?("description") or msg.include?("describe")
        m.reply("#{m.user.nick}: #{cs.code} = #{cs.name} (##{cs.units})")
        desc = cs.description
        doc = Nokogiri::HTML(desc)
        m.reply("#{m.user.nick}: #{doc.text}")
        
      elsif msg.include?("who takes") or msg.include?("who teaches") or msg.include?("who lectures")
        m.reply("#{m.user.nick}: #{cs.code} is coordinated by #{cs.coordinator}")
        
      elsif msg.include?("what faculty") or msg.include?("which faculty") or msg.include?("what school") or msg.include?("which school")
        m.reply("#{m.user.nick}: #{cs.code} is part of the school of #{cs.school}, in the faculty of #{cs.faculty}")
        
      elsif msg.include?("what plans") or msg.include?("plans for")
        ps = cs.uq_course_groups.uq_plans.collect { |pl| 
          pg = pl.uq_program
          "#{pg.name} / #{pl.name}" 
          }
        if (sz=ps.size) > 4
          ps = ps.join("\n")
          url = Pastebin.paste(ps, "UQBot")
          m.reply("#{m.user.nick}: #{cs.code} belongs to #{sz} plans, list at #{url}")
        else
          m.reply("#{m.user.nick}: #{cs.code} is found in #{ps.join(', ')}")
        end
        
      elsif msg.match(/depend(s?) on/)
        deps = cs.dependents.collect { |c| c.dependent.code }.join(", ")
        m.reply("#{m.user.nick}: Courses which require #{cs.code}: #{deps}")
        
      elsif msg.include?("offered")
        profs = cs.uq_course_profiles.collect { |p| "#{p.semester} (#{p.location}, #{p.mode})" }.join(", ")
        m.reply("#{m.user.nick}: #{cs.code} offerings: #{profs}")
        
      elsif (msg.include?("assessment") or msg.include?("assignments")) and msg.include?("list")
        pro = cs.uq_course_profiles.select { |p| p.current }.first
        if (pro.profileId < 0)
          pro = cs.uq_course_profiles.select { |p| p.profileId > 0 }.first
        end
        tasks = pro.uq_assessment_tasks.collect { |t| "#{t.name} (#{t.weight}, #{t.due_date})" }.join(", ")
        m.reply("#{m.user.nick}: #{cs.code} assessment: #{tasks}")
        
      elsif msg.include?("due") and (msg.include?("when is") or msg.include?("when's"))
        mm = msg.downcase.gsub(codes[0], "").gsub("due", "").gsub("when is", "").gsub("when's","")
        mm = mm.gsub(/[^a-z0-9 ]/, "").chomp.strip
        mms = mm.split
        
        pro = cs.uq_course_profiles.select { |p| p.current }.first
        if (pro.profileId < 0)
          pro = cs.uq_course_profiles.select { |p| p.profileId > 0 }.first
        end
        tasks = pro.uq_assessment_tasks.select { |t| 
          s = t.name.downcase + t.description.downcase
          mms.collect { |mm| s.include?(mm) }.select { |v| !v }.size == 0
        }
        tasks = tasks.collect { |t| "#{t.name} is due #{t.due_date} (weight #{t.weight})" }.join(", and ")
        m.reply("#{m.user.nick}: #{tasks}")
      end
    end
  end
end

Daemons.run_proc('uqircd',
                  :hard_exit => true,
                  :dir_mode => :system,
                  :backtrace => true,
                  :log_output => true) do
  bot.start
end
