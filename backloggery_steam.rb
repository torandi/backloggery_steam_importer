#!/usr/bin/env ruby
#encoding: utf-8

require 'json'
require 'mechanize'
require 'highline/import'

backloggery_url = "http://backloggery.com"

if ARGV.length < 1 || ARGV.length > 2
	puts "Usage: ./backloggery_steam.rb backloggery_username [steam_username]"
	exit -1 
end

backloggery_username = ARGV[0].downcase
if ARGV.length == 1
	steam_username = ARGV[0]
else
	steam_username = ARGV[1]
end

def ugly_hack_mechanize_is_retarded(str)
	str.force_encoding('utf-8').chars.select{|i| i.valid_encoding?}.join
end

puts "Steam user: #{steam_username}"
puts
puts "=== Backloggery ==="
puts "Username: #{backloggery_username}"
backloggery_password = ask("Backloggery password:  ") { |q| q.echo = "" }

backloggery = Mechanize.new { |agent| agent.follow_meta_refresh = true }
backloggery.get(backloggery_url) do |login|
	page = login.form do |form|
		form['username'] = backloggery_username
		form['password'] = backloggery_password
	end.submit
	if page.uri.to_s.end_with? "login.php"
		puts "Login failed!"
		exit 1
	else 
		puts "Login successful!"
	end
end

puts "Fetching already added games..."
existing_games = []
backloggery.get("http://backloggery.com/ajax_moregames.php?user=#{backloggery_username}&console=Steam&rating=&status=&unplayed=&own=&search=&comments=&region=&region_u=0&wish=&alpha=&temp_sys=ZZZ&total=2&aid=1&ajid=0") do |page|
	page.search("section.gamebox").each do |game|
		header = game.css("h2")
		name = header.css("b").text
		if name.length > 0
			existing_games << name.chomp
		end
	end
end

puts "Fetching backloggery new game form..."

backloggery.get("http://backloggery.com/newgame.php?user=#{backloggery_username}") do |page|
	page.encoding = 'utf-8'
	@new_game_form = page.form;
end

puts "Fetching steam game list..."

steam = Mechanize.new { |agent| agent.follow_meta_refresh = true }

steam.get("http://steamcommunity.com/id/#{steam_username}/games?tab=all") do |page|
	page.encoding = 'utf-8'
	@gameraw = ugly_hack_mechanize_is_retarded(page.body.match(/rgGames = .*?;/m).to_s.gsub("rgGames = ","").gsub(";","").gsub("\\/","/"))
end

puts "Uploading steam games..."

games = JSON.parse(@gameraw)
c = 0
games.each do |game|
	game_name = ugly_hack_mechanize_is_retarded(game["name"].chomp)
	game_name = game_name.gsub("\u2122", "") # remove (tm)

	if existing_games.include? game_name
		next
	end

	appid = game["appid"]
	@new_game_form['name'] = game_name
	@new_game_form['console'] = "Steam"
	@new_game_form['note'] = "Playtime: #{game['hours_forever']}h"
	@new_game_form['submit2'] = "Stealth Add"

	if game["availStatLinks"]["achievements"]
		url = game["friendlyURL"]
		steam.get("http://steamcommunity.com/id/#{steam_username}/stats/#{url}/?tab=achievments") do |page|
			block = page.search(".//div[@id='topSummaryAchievements']")
			achievment_count = block.children()[0].to_s.match(/(\d+) of (\d+)/)
			if achievment_count
				@new_game_form['achieve1'] = achievment_count[1]
				@new_game_form['achieve2'] = achievment_count[2]
			else
				puts "Error for #{game_name} achievments"
			end
		end
	end

	# Check if DLC:
	steam.get("http://store.steampowered.com/app/#{appid}") do |page|
		page.encoding = 'utf-8'
		dlc = page.body.match("Requires the base game.*?<a .*?>(.*?)</a>")
		if dlc
			@new_game_form['comp'] = dlc[1].chomp.force_encoding("utf-8").gsub("\u2122", "") # steam have a tendency of adding (tm) to the end of game names here, but not otherwise
		else
			@new_game_form['comp'] = game_name
		end
	end

	@new_game_form.submit


	c+= 1
	puts "#{game_name} uploaded (#{c}/#{games.length - existing_games.length})"
end

