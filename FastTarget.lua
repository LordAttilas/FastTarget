--[[
Copyright © 2024, from
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
    * Neither the name of Tab nor the
    names of its contributors may be used to endorse or promote products
    derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL from20020516 BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]
_addon.name = 'FastTarget'
_addon.author = 'Atilas'
_addon.version = '2.1'
_addon.commands = {'FastTarget','ft'}
_addon.language = 'english'

--[[ 
-------------INSTRUCTIONS---------------
* Allow to freely target using default TAB, ALT-TAB, F8 or any custom keys while in combat or locked to a target. 
* ESC will cancel sub-targeting and still allow quick peak at other mobs around.
* ENTER will select the sub-target and engage right away.
]]

require('sets')
config = require('config')

default_settings = {}
default_settings.use_st_target = true
default_settings.use_auto_next_st = true
default_settings.use_auto_attack = true
default_settings.custom_left = 0
default_settings.custom_right = 0
default_settings.custom_nearest = 0
settings = config.load('data\\settings.xml',default_settings)

debugmode = false
bindmode = 0
targeting = false
key_shift = 42
key_control = 29
key_alt = 56
key_esc = 1
key_enter = 28
key_tab = 15
key_f8 = 66
key_f = 33
key_minus = 12
key_alt = 56
key_ctrl = 29

playerStatus = -1
chat_log_open = false
chat_log_expanded = false

find_distance = 21
find_tolerance = 2
find_angle = 120
find_mobs = {}
find_mob_backward = false
find_last_dying_mob = nil
find_protectLoop = 0
clock = os.clock()

function fullReset()
	targeting = false
	playerStatus = -1
	chat_log_open = false
	chat_log_expanded = false
	find_last_dying_mob = nil
	find_mobs = {}
	find_protectLoop = 0
end

function reset()
	targeting = false
	find_last_dying_mob = nil
	find_mobs = {}
	find_protectLoop = 0
end

local function contains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

function ComputeRelativeDirection(playerpos, target)
	local vectorX = (target.x - playerpos.x)
	local vectorY = (target.y - playerpos.y)
	local quatranCorection = 0
	if vectorX < 0 then
		quatranCorection = 180
	elseif vectorY < 0 then
		quatranCorection = 360
	end
	local playerdirection = math.fmod((playerpos.facing*180/3.1413)+450,360)
	local direction = math.fmod(360 - (math.deg(math.atan((target.y - playerpos.y)/(target.x - playerpos.x))) + quatranCorection) + 90,360)
	return math.fmod(direction - playerdirection + 360,360)
end


function get_next_mob()
    local player = windower.ffxi.get_player()
	local targetIndex = player.target_index
	local currentTarget = nil
	if targetIndex ~= nil then
		currentTarget = windower.ffxi.get_mob_by_index(targetIndex)
		if currentTarget.hpp == 0 or currentTarget.status == 2 or currentTarget.status == 3 then
			find_last_dying_mob = currentTarget
			if debugmode then windower.add_to_chat(207, 'FastTarget - Current target is dying.') end
		else
			find_last_dying_mob = nil
		end
	end
	local mobs = windower.ffxi.get_mob_array()
		
	local mob_list = {}
	for _, mob in pairs(mobs) do
		if mob.valid_target and mob.spawn_type == 16 and not (mob.status == 2 or mob.status == 3) and math.sqrt(mob.distance)<find_distance and (currentTarget == nil or mob.id ~= currentTarget.id) and (find_last_dying_mob == nil or mob.id ~= find_last_dying_mob.id) then
			table.insert(mob_list, mob)
		end
	end
	local mobsSorted = table.sort(mob_list, function(a, b) return math.sqrt(a.distance) < math.sqrt(b.distance) end)
	
	local closest_mobs = {}
	if #mobsSorted > 0 then
	
		local min_distance = math.sqrt(mobsSorted[1].distance)
		local tolerance = find_tolerance
		local max_distance = min_distance + tolerance
		
		for _, mob in pairs(mobsSorted) do
			if mob.valid_target and mob.spawn_type == 16 and not (mob.status == 2 or mob.status == 3) and math.sqrt(mob.distance)<find_distance and (currentTarget == nil or mob.id ~= currentTarget.id) and (find_last_dying_mob == nil or mob.id ~= find_last_dying_mob.id) then
				local playerMob = windower.ffxi.get_mob_by_id(player.id)
				local mobDirection = ComputeRelativeDirection(playerMob,mob)
				
				if mobDirection < (find_angle/2) or mobDirection > (360-(find_angle/2)) then
					
					if math.sqrt(mob.distance) <= max_distance then
						table.insert(closest_mobs, mob.id)
					else
						break
					end
				
					if #closest_mobs == 1 then
						find_mob_backward=mobDirection>300
					end
				end
			end
		end
	end

	if #closest_mobs == 0 then
        if debugmode then windower.add_to_chat(207, 'FastTarget - Cannot automatically find next valid sub-target.') end
    end
	
	return closest_mobs
end


windower.register_event('addon command', function(...)

	local arg = {...}
	if #arg == 1 and arg[1]:lower() == 'bind' then	
		windower.add_to_chat(200, 'FastTarget - Automatic key bind')
		windower.add_to_chat(200, '  Press to register three custom keys one after then other.')
		windower.add_to_chat(200, '  Once completed they will be saved as an alternative do the default Tab, Alt-Tab and F8.')
		windower.add_to_chat(200, 'Start pressing keys now... (Cancel using ESC)')
		windower.add_to_chat(200, '  1) Press key to bind target left:')
		bindmode = 1
	
	elseif #arg == 1 and arg[1]:lower() == 'unbind' then
		settings.custom_left = 0
		settings.custom_right = 0
		settings.custom_nearest = 0
		settings:save()
		windower.add_to_chat(200, 'FastTarget - Custom binding removed')
	
	elseif #arg == 1 and arg[1]:lower() == 'debug' then
		if debugmode == true then
			debugmode = false
			windower.add_to_chat(200, 'FastTarget - Stoping debug mode')
		else
			debugmode = true
			windower.add_to_chat(200, 'FastTarget - Starting debug mode.')
		end
		
	elseif #arg == 1 and arg[1]:lower() == 'target' then
		if settings.use_st_target == true then
			settings.use_st_target = false
			windower.add_to_chat(200, 'FastTarget - Using <stnpc> for out-of-combat target override.')
		else
			settings.use_st_target = true
			windower.add_to_chat(200, 'FastTarget - Using <st> for out-of-combat target override.')
		end
		settings:save()
	
	elseif #arg == 1 and arg[1]:lower() == 'search' then
		if settings.use_auto_next_st == true then
			settings.use_auto_next_st = false
			windower.add_to_chat(200, 'FastTarget - Default nearest sub-target behavior (F8).')
		else
			settings.use_auto_next_st = true
			windower.add_to_chat(200, 'FastTarget - Automatically search the next, nearest and in front sub-target (F8).')
		end
		settings:save()
		
	elseif #arg == 1 and arg[1]:lower() == 'attack' then
		if settings.use_auto_attack == true then
			settings.use_auto_attack = false
			windower.add_to_chat(200, 'FastTarget - Will not Automatically attack sub-target when current target die.')
		else
			settings.use_auto_attack = true
			windower.add_to_chat(200, 'FastTarget - Automatically attack sub-target when current target die.')
		end
		settings:save()

	elseif #arg == 0 or (#arg == 1 and arg[1]:lower() == 'help') then
		windower.add_to_chat(200, 'FastTarget - Allows instant override of manual lock, in-combat lock, action menu lock, or chat history lock for faster target switching at any time using the default Tab, Alt-Tab, and F8 keys with the in-game sub-target function.')
		windower.add_to_chat(200, 'Available Options:')
		windower.add_to_chat(200, '  //ft search - Toggle automatic search for next sub-target when using nearest keys.')
		windower.add_to_chat(200, '  //ft attack - Toggle automatic attack of sub-target when current target die.')
		windower.add_to_chat(200, '  //ft target - Change out-of-combat target selection between all or npc.')
		windower.add_to_chat(200, '  //ft bind   - Bind additional left, right and nearest target custom keys.')
		windower.add_to_chat(200, '  //ft unbind - Reset custom key binds.')
		windower.add_to_chat(200, '  //ft debug - Toggle debug mode.')
		windower.add_to_chat(200, '  //ft help   - Displays this text.')
	else
		windower.add_to_chat(167, 'FastTarget - Invalid command. //ft help for valid options.')
	end
end)

windower.register_event('status change',function(new,old)
    windower.debug('status change '..new)
    if T{2,3,4}:contains(old) or T{2,3,4}:contains(new) then 
		fullReset()
		return 
	end

	if debugmode then windower.add_to_chat(207, 'FastTarget - Status change detected new='..new..' old='..old) end
	playerStatus = new
end)

windower.register_event('zone change',function(new_id, old_id) 
	fullReset()
end)

windower.register_event('keyboard',function(dik,pressed,flags,blocked)
    --if pressed then windower.add_to_chat(207, dik) end
	
	--Custom map keypress
	if bindmode == 0 then
		if dik==settings.custom_nearest then
			windower.send_command('setkey f8 '..(pressed and 'down' or 'up'))
		elseif dik==settings.custom_left then
			if pressed then
				windower.send_command('setkey shift down;setkey tab down;wait 0.2;setkey shift up')
			else
				windower.send_command('setkey tab up;setkey shift up')
			end
		elseif dik==settings.custom_right then
			windower.send_command('setkey tab '..(pressed and 'down' or 'up'))
		end
	end
	
	if pressed and not windower.chat.is_open()  then
	
		if S{key_f,key_esc,key_enter}[dik] then
			--Detect chat log status
			local chat_log_open_previous = chat_log_open
			
			if dik == key_f then
				chat_log_open = true
			elseif dik == key_enter then
				if chat_log_open then chat_log_expanded = true end
			elseif dik == key_esc then
				if chat_log_expanded then chat_log_expanded = false
				elseif chat_log_open then chat_log_open = false end
			end
			if debugmode then
				if chat_log_expanded and dik == key_f then
					windower.add_to_chat(207, 'FastTarget - Chat log is expanded page change.')
				elseif chat_log_expanded then
					windower.add_to_chat(207, 'FastTarget - Chat log is expanded.')
				elseif chat_log_open then
					windower.add_to_chat(207, 'FastTarget - Chat log is open.')
				elseif chat_log_open_previous then
					windower.add_to_chat(207, 'FastTarget - Chat log is closed.')
				end
			end
		end
		
		if bindmode > 0 and not (S{key_tab,key_f8,key_shift,key_control,key_alt,key_enter,key_minus,key_alt,key_ctrl}[dik]) then
			--Bind mode
			if debugmode then windower.add_to_chat(207, 'FastTarget - Bindmode #'..bindmode) end
			
			if dik==key_esc then
				windower.add_to_chat(167, 'FastTarget - Custom binding cancelled !')
				bindmode = 0
			else
				if bindmode == 1 then
					settings.custom_left = dik
					if debugmode then windower.add_to_chat(207, 'FastTarget - Custom target left bound to '..settings.custom_left) end
					windower.add_to_chat(200, '  2) Press key to bind target right:')
					bindmode = bindmode + 1
				elseif bindmode == 2 then
					settings.custom_right = dik
					if debugmode then windower.add_to_chat(207, 'FastTarget - Custom target right bound to '..settings.custom_right) end
					windower.add_to_chat(200, '  3) Press key to bind target nearest:')
					bindmode = bindmode + 1
				elseif bindmode == 3 then
					settings.custom_nearest = dik
					if debugmode then windower.add_to_chat(207, 'FastTarget - Custom target nearest bound to '..settings.custom_nearest) end
					windower.add_to_chat(200, 'FastTarget - Custom binding completed')
					bindmode = 0
					settings:save()
				end
				
			end
	
		elseif S{key_esc,key_enter,key_tab,key_f8,key_minus,key_alt,key_ctrl,settings.custom_left,settings.custom_right,settings.custom_nearest}[dik] then
			--Target overrde
			local info = windower.ffxi.get_info()
			local player = windower.ffxi.get_player()
			
			if player and playerStatus == -1 then
				--Initial player status after plugin is loaded
				playerStatus = player.status
			end
			
			--Automatic Chatlog away
			local chatLogWasOpen = false
			if chat_log_open and not chat_log_expanded and S{key_tab,key_f8,key_minus,key_alt,key_ctrl,settings.custom_left,settings.custom_right,settings.custom_nearest}[dik] then
				windower.send_command('setkey escape down;wait 0.2;setkey escape up')
				chat_log_open = false
				chatLogWasOpen = true
				if debugmode then windower.add_to_chat(207, 'FastTarget - Chat log out of the way !!') end
			end
			
			if player and ((not chatLogWasOpen and info.menu_open) or playerStatus == 1 or player.target_locked == true) then
				
				if not targeting and ((S{key_tab,key_f8,settings.custom_left,settings.custom_right,settings.custom_nearest}[dik] and flags == 0) or (dik==key_tab and flags == 1)) then
					targeting = true
					
					local target = nil
					local targetIndex = player.target_index
					if targetIndex ~= nil then
						target = windower.ffxi.get_mob_by_index(targetIndex)
					end
					
					--Detect if in combat or nearly just death target
					local inCombat = playerStatus == 1 or ( target and (target.status == 2 or target.status == 3))
					local targetCommand = inCombat and '/attack' or '/target'
					local targetSelection = settings.use_st_target and '<st>' or '<stnpc>'
					
					if debugmode then
						if inCombat then
							windower.add_to_chat(207, 'FastTarget - Overriding in combat lock with /attack '..targetSelection)
						elseif player.target_locked then
							windower.add_to_chat(207, 'FastTarget - Overriding target lock with /target '..targetSelection)
						else
							windower.add_to_chat(207, 'FastTarget - Overriding menu lock with /target '..targetSelection)
						end
					end
					if chatLogWasOpen then
						--Add small delay to avoid message we can't use this command while chatlog is open
						windower.send_command('@input ;wait 0.1;input '..targetCommand..' '..targetSelection)
					else
						windower.chat.input(targetCommand..' '..targetSelection)
					end
					
					--Activate autotarget if enable
					if settings.use_auto_next_st and S{key_f8,settings.custom_nearest}[dik] then
						find_mobs = get_next_mob()
					end
					
					return true
			
				elseif S{key_esc,key_enter}[dik] then --Esc or Enter
					reset()
				end
			
			elseif targeting == true and S{key_esc,key_enter}[dik] then
				reset()
			end
		end
    end
end
)


windower.register_event("prerender", function()
	--Automatic sub-target selection
	if #find_mobs > 0 and os.clock() - clock > 0.10 then
		clock = os.clock()
		
		if find_protectLoop==0 then
			if debugmode then windower.add_to_chat(207, 'FastTarget - Searching next target (out of '..#find_mobs..')') end
			if targeting then windower.send_command('setkey home down;wait 0.2;setkey home up') end--Used to get view straight for faster sub-target search and reliability
		end
		find_protectLoop = find_protectLoop + 1
		local stmob = windower.ffxi.get_mob_by_target('st')
		if stmob~=nil then
			if contains(find_mobs,stmob.id) then
				find_mobs = {}
				find_protectLoop = 0
				
				if find_last_dying_mob then
					--This is used to trap a little earlier when a mobn just died and we pressed to Automatically find a new target quickly after.
					if debugmode then windower.add_to_chat(200, 'FastTarget - Found one and attacking since current just died !!') end
					windower.send_command('setkey enter down;wait 0.2;setkey enter up')
					reset() --Since we automatically confirm sub-target we want to remove targeting toggle.
				else
					if debugmode then windower.add_to_chat(207, 'FastTarget - Found one !!') end
				end
				
			else
				if debugmode then windower.add_to_chat(207, 'FastTarget - '..(find_mob_backward and 'Backward' or 'Forward')) end
				if find_mob_backward then
					windower.send_command('setkey shift down;setkey tab down;wait 0.05;setkey tab up;setkey shift up')
				else
					windower.send_command('setkey tab down;wait 0.05;setkey tab up')
				end
			end
		end
		
		if find_protectLoop >= 20 then
			if debugmode then windower.add_to_chat(207, 'FastTarget - Too much targets...') end
			windower.send_command('setkey f8 down;wait 0.2;setkey f8 up')
			find_mobs = {}
			find_protectLoop = 0
		end
	end
	
	--Automatic sub-target selection on mob dying
	if settings.use_auto_attack and targeting and #find_mobs == 0 and os.clock() - clock > 0.25 then
		clock = os.clock()
		
		local currentSubTarget = windower.ffxi.get_mob_by_target('st')
		
		if currentSubTarget then
			local currentTarget = windower.ffxi.get_mob_by_target('t')
			
			if debugmode then 
				if currentTarget and currentSubTarget and currentTarget.id ~= currentSubTarget.id then windower.add_to_chat(207, 'FastTarget - Watching current target...') end
			end
			if not currentTarget or (currentTarget.hpp==0 or currentTarget.status == 2 or currentTarget.status == 3) then
				if debugmode then windower.add_to_chat(200, 'FastTarget - Dying mob detected so automatically applying sub-target !!') end
				windower.send_command('setkey enter down;wait 0.2;setkey enter up')
				reset() --Since we automatically confirm sub-target we want to remove targeting toggle.
			end
		end
	end
	
end)
