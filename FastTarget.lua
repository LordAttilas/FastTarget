--[[
Copyright © 2025, from
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
_addon.version = '3.2'
_addon.commands = {'FastTarget','ft'}
_addon.language = 'english'

--[[ 
-------------INSTRUCTIONS---------------
* Allow to freely target using default TAB, ALT-TAB, F8 or any custom keys while in combat or locked to a target. 
* ESC will cancel sub-targeting and still allow quick peak at other mobs around.
* ENTER will select the sub-target and engage right away.
]]

require('sets')
local config = require('config')
local texts = require('texts')

local default_settings = {}
default_settings.use_st_target = true
default_settings.use_auto_next_st = true
default_settings.use_auto_switch = true
default_settings.use_allow_queue = true
default_settings.custom_left = 0
default_settings.custom_right = 0
default_settings.custom_nearest = 0

default_settings.display_ui = true
default_settings.bg = {}
default_settings.bg.visible = false
default_settings.pos = {}
default_settings.pos.x = -178
default_settings.pos.y = 21
default_settings.text = {}
default_settings.text.font = 'Arial'
default_settings.text.size = 12
default_settings.text.stroke = {}
default_settings.text.stroke.alpha = 255
default_settings.text.stroke.width = 2
default_settings.flags = {}
default_settings.flags.right = false
local settings = config.load('data\\settings.xml',default_settings)

local mainuitext = texts.new('${distance||%.1f}\n${hpp||%.0f}%\n${nextTarget}', settings)
local color_red = '\\cs(255,0,0)'
local color_green =  '\\cs(0,255,0)'
local color_blue = '\\cs(0,0,255)'
local color_cyan = '\\cs(0,200,255)'
local color_orange = '\\cs(255,155,0)'
local color_yellow = '\\cs(255,255,0)'
local color_end = '\\cr'

local debugmode = false
local bindmode = 0
local subTargeting = false
local key_shift = 42
local key_control = 29
local key_alt = 56
local key_esc = 1
local key_enter = 28
local key_tab = 15
local key_f8 = 66
local key_f = 33
local key_minus = 12
local key_alt = 56
local key_ctrl = 29

local playerStatus = -1
local chat_log_open = 0
local chat_log_expanded = false

local find_distance = 31
local find_tolerance_radius = 2
local find_angle = 120
local find_max_distance_auto_queue = 6
local find_mobs = {}
local find_mob_backward = false
local find_mob_first_direction = 0
local find_current_mob_dying = nil
local find_queue_target_activated = false
local find_queue_target_current_id = 0
local find_queue_target_next_id = 0
local find_queue_validate_next_id = 0
local find_queue_validate_loop = 0
local find_protectLoop = 0

local main_target_changed = false
local main_target = nil

function fullReset()
	subTargeting = false
	playerStatus = -1
	chat_log_open = 0
	chat_log_expanded = false
	find_current_mob_dying = nil
	find_mobs = {}
	find_protectLoop = 0
	find_queue_target_activated = false
	find_queue_target_current_id = 0
	find_queue_target_next_id = 0
	find_queue_validate_loop = 0
end

function reset()
	subTargeting = false
	find_current_mob_dying = nil
	find_mobs = {}
	find_protectLoop = 0
	find_queue_target_activated = false
	find_mob_first_direction = 0
end



local watchingThrottle = os.clock()
local lastThrottledMsg = nil
function throttled_add_to_chat(color,msg)
	if msg == nil then return end
	if lastThrottledMsg == nil or msg ~= lastThrottledMsg or os.clock() - watchingThrottle > 5 then
		watchingThrottle = os.clock()
		lastThrottledMsg = msg
		windower.add_to_chat(color, msg)
	end
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

function is_mob(target)
	if target ~= nil and target.valid_target and target.spawn_type == 16 then
		return true
	end
	return false
end

function is_mob_in_front(mob)
	if not mob then return false end

	local player = windower.ffxi.get_player()
	local playerMob = windower.ffxi.get_mob_by_id(player.id)
	local mobDirection = ComputeRelativeDirection(playerMob,mob)
		
	if mobDirection < (find_angle/2) or mobDirection > (360-(find_angle/2)) then
		return true
	end
	return false
end

function is_valid_target(mob)
	if mob ~= nil and mob.valid_target and mob.spawn_type == 16 and not (mob.status == 2 or mob.status == 3) then 
		return true 
	end
	return false
end

function is_proper_target(mob)
	if not mob then return false end
	
	local player = windower.ffxi.get_player()
	local playerMob = windower.ffxi.get_mob_by_id(player.id)
	local targetIndex = player.target_index
	local currentTarget = nil
	if targetIndex ~= nil then
		currentTarget = windower.ffxi.get_mob_by_index(targetIndex)
	end
	local mobDistance = math.sqrt(mob.distance)

	if is_valid_target(mob) and mobDistance<find_distance and (currentTarget == nil or mob.id ~= currentTarget.id) then
		local mobDirection = ComputeRelativeDirection(playerMob,mob)
		
		if mobDirection < (find_angle/2) or mobDirection > (360-(find_angle/2)) then
			return true
		end			
	end
	return false
end


function get_next_mob()
    local player = windower.ffxi.get_player()
	local playerMob = windower.ffxi.get_mob_by_id(player.id)
	local targetIndex = player.target_index
	local currentTarget = nil
	if targetIndex ~= nil then
		currentTarget = windower.ffxi.get_mob_by_index(targetIndex)
		if currentTarget.hpp == 0 or currentTarget.status == 2 or currentTarget.status == 3 then
			find_current_mob_dying = currentTarget
			if debugmode then windower.add_to_chat(207, 'FastTarget - Current target is dying.') end
		else
			find_current_mob_dying = nil
		end
	end
	
	local minimumDistance = find_distance
	local mobs = windower.ffxi.get_mob_array()
	local mob_list = {}
	for _, mob in pairs(mobs) do
		local mobDistance = math.sqrt(mob.distance)

		if mob.valid_target and mob.spawn_type == 16 and not (mob.status == 2 or mob.status == 3) and mobDistance<find_distance and  (currentTarget == nil or mob.id ~= currentTarget.id) and (find_current_mob_dying == nil or mob.id ~= find_current_mob_dying.id) then
			local mobDirection = ComputeRelativeDirection(playerMob,mob)
			
			if mobDirection < (find_angle/2) or mobDirection > (360-(find_angle/2)) then
				--if debugmode then windower.add_to_chat(207, 'FastTarget - Adding mob ('..mob.id..') '..mob.name..' (Dis:'..(math.floor(math.sqrt(mob.distance) * 10)/ 10)..') (Dir:'..math.floor(mobDirection)..') (Z:'..(math.floor(mob.z * 10)/ 10)..') to list') end
				table.insert(mob_list, mob)
				if mobDistance < minimumDistance then minimumDistance = mobDistance end
			end			
		end
	end
	
	local closest_mobs = {}
	if #mob_list > 0 then
		local max_distance = minimumDistance + find_tolerance_radius	
		for _, mob in pairs(mob_list) do
						
			if math.sqrt(mob.distance) <= max_distance then
				table.insert(closest_mobs, mob.id)
				refusedCheck = false

				if #closest_mobs == 1 then
					local mobDirection = ComputeRelativeDirection(playerMob,mob)
					find_mob_backward = mobDirection > 300 --Quick check to start finding mob in the right direction
					find_mob_first_direction = mobDirection
				end
			end
		end
	end

	if #closest_mobs == 0 then
        if debugmode then windower.add_to_chat(207, 'FastTarget - Cannot automatically find next valid sub-target.') end
    end
	
	return closest_mobs
end


local function recursiveDisplayUI()

	local wasUpdated = false
	if settings.display_ui == true then 
	
		local player = windower.ffxi.get_player()
		if player then
			local t = windower.ffxi.get_mob_by_index(player.target_index or 0)
			if t and t.id ~= player.id and is_mob(t) then
				mainuitext.distance = t.distance:sqrt()
				mainuitext.hpp = t.hpp
				if find_queue_validate_next_id > 0 then
					mainuitext.nextTarget = color_orange.."SWITCH"..color_end
				elseif find_queue_target_next_id > 0 then
					mainuitext.nextTarget = color_green.."SET"..color_end
				elseif subTargeting then
					if find_queue_target_activated then
						mainuitext.nextTarget = color_yellow.."NEXT..."..color_end
					else
						mainuitext.nextTarget = color_cyan.."NEW..."..color_end
					end
				else
					mainuitext.nextTarget = ""
				end
				mainuitext:visible(true)
				wasUpdated = true
				
				recursiveDisplayUI:schedule(0.1)				
			end	
		end
	end
	
	if not wasUpdated then
		mainuitext.distance = 0
		mainuitext.hpp = 0
		mainuitext.nextTarget = ""
		mainuitext:visible(false)
	end

end


local function displayUI()
	if settings.display_ui == true and texts.visible(mainuitext, visible) == false then 
		recursiveDisplayUI()
	end
end

local function validateNextTarget()
	if find_queue_validate_loop == 0 then 
		if debugmode then windower.add_to_chat(200, 'FastTarget - Checking if we are on the good last sub-target...') end
	end
	if find_queue_validate_next_id > 0 and find_queue_validate_loop <= 5 then
		local stmob = windower.ffxi.get_mob_by_target('lastst')
		if stmob and stmob.id == find_queue_validate_next_id then
			local currentTarget = windower.ffxi.get_mob_by_target('t')
			if not currentTarget or currentTarget.id ~= find_queue_validate_next_id or playerStatus==0 then
				windower.send_command('@input /attack <lastst>')
				if debugmode then windower.add_to_chat(200, 'FastTarget - Still not targeting the last sub-target, trying to switch again now...') end
				find_queue_validate_loop = find_queue_validate_loop + 1
				validateNextTarget:schedule(1)
				return
			else
				if debugmode then windower.add_to_chat(200, 'FastTarget - Target set properly.') end
			end
		else
			if debugmode then windower.add_to_chat(200, 'FastTarget - Lost last sub-target.') end
		end
	end
	find_queue_validate_next_id = 0
	find_queue_validate_loop = 0
end


local function switchNextTarget()

	if settings.use_auto_switch and #find_mobs == 0 and (subTargeting or find_queue_target_next_id > 0) then
	
		if subTargeting then
			--Current sub-target is active and waiting for mob to die
			local currentSubTarget = windower.ffxi.get_mob_by_target('st')
			if currentSubTarget and is_valid_target(currentSubTarget) then
				local currentTarget = windower.ffxi.get_mob_by_target('t')
				
				if not currentTarget or (is_mob(currentTarget) and (currentTarget.hpp==0 or currentTarget.status == 2 or currentTarget.status == 3)) then
					if find_queue_target_activated then
						if debugmode then windower.add_to_chat(200, 'FastTarget - Dying mob detected so automatically applying unselected last sub-target !!') end
						fullReset()
						windower.send_command('setkey enter down;wait 0.2;setkey enter up ;wait 0.2;input /attack <lastst>')						
					else
						if debugmode then windower.add_to_chat(200, 'FastTarget - Dying mob detected so automatically applying sub-target !!') end
						fullReset()
						windower.send_command('setkey enter down;wait 0.2;setkey enter up')
					end						
					return
				elseif debugmode and is_mob(currentTarget) then 
					if currentTarget.id ~= currentSubTarget.id then throttled_add_to_chat(207, 'FastTarget - Watching current target to die (Active sub-target)...') end
				end
			end
		else 
			--Active last sub-target is selected and waiting for mob to die
			local lastSubTarget = windower.ffxi.get_mob_by_target('st','lastst')
			if not lastSubTarget then
				if debugmode then windower.add_to_chat(200, 'FastTarget - No more last sub-target. Cancelling auto-target next...') end
				fullReset()
				return
			end
			
			local currentTarget = windower.ffxi.get_mob_by_target('t')
			if not currentTarget then
				if debugmode then windower.add_to_chat(200, 'FastTarget - No more target. Ignoring last sub-target !!') end
				fullReset()
				return
			elseif is_mob(currentTarget) then
				if currentTarget.id ~= find_queue_target_current_id then						
					if debugmode then windower.add_to_chat(200, 'FastTarget - Missed dying mobs and already on new native autotarget so automatically attacking last sub-target !!') end
					find_queue_validate_next_id = find_queue_target_next_id
					fullReset()
					windower.send_command('@input /attack <lastst>')
					validateNextTarget:schedule(0.5) 
				elseif (currentTarget.hpp==0 or currentTarget.status == 2 or currentTarget.status == 3) then						
					if debugmode then windower.add_to_chat(200, 'FastTarget - Dying mob detected so automatically attacking last sub-target !!') end
					find_queue_validate_next_id = find_queue_target_next_id
					fullReset()
					windower.send_command('@input /attack <lastst>')
					validateNextTarget:schedule(1) 
				elseif debugmode then
					throttled_add_to_chat(207, 'FastTarget - Watching current target to die (Last sub-target)...')
				end
			end
		end
	
		switchNextTarget:schedule(0.1) 
	
	end

end


local function findNextTarget()
	
	if #find_mobs > 0 then
	
		if find_protectLoop==0 then
			if debugmode then windower.add_to_chat(207, 'FastTarget - Searching next target (out of '..#find_mobs..')') end
		elseif find_protectLoop==5 then
			if subTargeting then windower.send_command('setkey home down;wait 0.2;setkey home up') end--Used to get view straight for faster sub-target search and reliability
		end
		
		local stmob = windower.ffxi.get_mob_by_target('st')
		if stmob~=nil then
			if contains(find_mobs,stmob.id) then
				find_mobs = {} --Stop seeking target we found one
				find_protectLoop = 0
				
				if find_current_mob_dying then
					--This is used to trap a little earlier when a mob just died and we pressed to Automatically find a new target quickly after.
					if debugmode then windower.add_to_chat(200, 'FastTarget - Found one and attacking since current just died !!') end
					if find_queue_target_activated then
						fullReset() --reset() --Since we automatically confirm sub-target we want to remove targeting toggle.
						windower.send_command('setkey enter down;wait 0.2;setkey enter up ;wait 0.2;input /attack <lastst>')
					else
						fullReset() --reset() --Since we automatically confirm sub-target we want to remove targeting toggle.
						windower.send_command('setkey enter down;wait 0.2;setkey enter up')
					end
					return
				else
					if debugmode then windower.add_to_chat(207, 'FastTarget - Found one !!') end
					switchNextTarget()
				end
				
			else
				if find_protectLoop == 1 then
					--Check where initial sub-target landed based on current camera view and adjust
					local playerMob = windower.ffxi.get_mob_by_id(windower.ffxi.get_player().id)
					local subtargetDirection = math.fmod(ComputeRelativeDirection(playerMob,stmob) + 180,360)
					local nearestTargetDirection = math.fmod(find_mob_first_direction + 180,360)
					
					if debugmode then windower.add_to_chat(207, 'FastTarget - subTargetDirection:'..math.floor(subtargetDirection)..' nearestTargetDirection: '..math.floor(nearestTargetDirection)) end
					find_mob_backward = nearestTargetDirection < subtargetDirection
				end	

				if debugmode then windower.add_to_chat(207, 'FastTarget - '..(find_mob_backward and 'Backward' or 'Forward')..' '..find_protectLoop) end
				if find_mob_backward then
					windower.send_command('setkey shift down;setkey tab down;wait 0.05;setkey tab up;setkey shift up')
				else
					windower.send_command('setkey tab down;wait 0.05;setkey tab up')
				end
			end
			
			find_protectLoop = find_protectLoop + 1
		end
		
		if find_protectLoop >= 20 then
			if debugmode then windower.add_to_chat(207, 'FastTarget - Too much targets...') end
			windower.send_command('setkey f8 down;wait 0.2;setkey f8 up')
			find_mobs = {}
			find_protectLoop = 0
		end
		
		findNextTarget:schedule(0.1) 
	end
end


local function trackLastSubTarget()

	if settings.use_auto_switch and settings.use_allow_queue and main_target_changed then
		
		if not subTargeting and find_queue_target_next_id == 0 and playerStatus == 1 then
			
			local lastSubTarget = windower.ffxi.get_mob_by_target('st','lastst')
			local currentTarget = windower.ffxi.get_mob_by_target('t')
			if currentTarget and lastSubTarget and currentTarget.id ~= lastSubTarget.id and is_valid_target(lastSubTarget) then
				if debugmode then windower.add_to_chat(200, 'FastTarget - Activating current mob tracking for automatic switch to last sub target') end
				main_target_changed = false
				find_queue_target_current_id = currentTarget.id
				find_queue_target_next_id = lastSubTarget.id
				switchNextTarget()
			end
		else
			trackLastSubTarget:schedule(2)
		end
	end

end


windower.register_event('status change',function(new,old)
    --windower.debug('status change '..new)
    if debugmode then windower.add_to_chat(207, 'FastTarget - Status change detected new='..new..' old='..old) end
	--if T{2,3,4}:contains(old) or T{2,3,4}:contains(new) then 
	
	playerStatus = new
	if T{2,3,4}:contains(new) then 
		if debugmode then windower.add_to_chat(207, 'FastTarget - FullReset from status change') end
		fullReset()
		return
	end
	
end)

windower.register_event('target change', function(index)

	local indexTarget = windower.ffxi.get_mob_by_index(index)
	if indexTarget then
		displayUI()
	end

	if settings.use_auto_switch then
		
		local activeSubTarget = windower.ffxi.get_mob_by_target('st')
		if not activeSubTarget then
			
			if main_target == nil or indexTarget == nil or main_target.id ~= indexTarget.id then
				if is_valid_target(indexTarget) then
					if debugmode then windower.add_to_chat(207, 'FastTarget - New main target detected '..indexTarget.id) end
					main_target = indexTarget
					main_target_changed = true
				else
					main_target = nil
					main_target_changed = false
				end
				
			end
		end
	end
end)

windower.register_event('zone change',function(new_id, old_id) 
	if debugmode then windower.add_to_chat(207, 'FastTarget - FullReset from zone change') end
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
	
	if pressed and not windower.chat.is_open() then
	
		--Detect chat log status
		if S{key_f,key_esc,key_enter}[dik] then
			local chat_log_open_previous = chat_log_open
			
			if dik == key_f and not chat_log_expanded then
				if chat_log_open == 1 then 
					chat_log_open = 2
				elseif chat_log_open == 2 then 
					chat_log_open = 0
				else 
					chat_log_open = 1 
				end
			elseif dik == key_enter then
				if chat_log_open == 1 then chat_log_expanded = true end
			elseif dik == key_esc then
				if chat_log_expanded then chat_log_expanded = false
				elseif chat_log_open > 0 then chat_log_open = 0 end
			end
			if debugmode then
				if chat_log_expanded and dik == key_f then
					windower.add_to_chat(207, 'FastTarget - Chat log is expanded page change.')
				elseif chat_log_expanded then
					windower.add_to_chat(207, 'FastTarget - Chat log is expanded.')
				elseif chat_log_open == 1 then
					windower.add_to_chat(207, 'FastTarget - Chat log is open.')
				elseif chat_log_open == 2 then
					windower.add_to_chat(207, 'FastTarget - Chat log is open in status bar.')
				elseif chat_log_open_previous > 0 then
					windower.add_to_chat(207, 'FastTarget - Chat log is closed.')
				end
			end
		end
		
		--Bind mode
		if bindmode > 0 and not (S{key_tab,key_f8,key_shift,key_control,key_alt,key_enter,key_minus,key_alt,key_ctrl}[dik]) then
			if debugmode then windower.add_to_chat(207, 'FastTarget - Bindmode #'..bindmode) end
			
			if dik==key_esc then
				windower.add_to_chat(167, 'FastTarget - Custom binding cancelled !')
				bindmode = 0
			else
				if bindmode == 1 then
					settings.custom_left = dik
					if debugmode then windower.add_to_chat(207, 'FastTarget - Custom target left bound to '..settings.custom_left) end
					windower.add_to_chat(200, '  2) Press key to bind target right (Tab):')
					bindmode = bindmode + 1
				elseif bindmode == 2 then
					settings.custom_right = dik
					if debugmode then windower.add_to_chat(207, 'FastTarget - Custom target right bound to '..settings.custom_right) end
					windower.add_to_chat(200, '  3) Press key to bind target nearest (F8):')
					bindmode = bindmode + 1
				elseif bindmode == 3 then
					settings.custom_nearest = dik
					if debugmode then windower.add_to_chat(207, 'FastTarget - Custom target nearest bound to '..settings.custom_nearest) end
					windower.add_to_chat(200, 'FastTarget - Custom binding completed')
					bindmode = 0
					settings:save()
				end
				
			end
	
		--Target override
		elseif S{key_esc,key_enter,key_tab,key_f8,key_minus,key_alt,key_ctrl,settings.custom_left,settings.custom_right,settings.custom_nearest}[dik] then
			local info = windower.ffxi.get_info()
			local player = windower.ffxi.get_player()
			
			if player and playerStatus == -1 then
				--Initial player status after plugin is loaded
				playerStatus = player.status
			end
			
			--Automatic Chatlog away
			local chatLogWasOpen = false
			if chat_log_open > 0 and not chat_log_expanded and S{key_tab,key_f8,key_minus,key_alt,key_ctrl,settings.custom_left,settings.custom_right,settings.custom_nearest}[dik] then
				windower.send_command('setkey escape down;wait 0.2;setkey escape up')
				chat_log_open = 0
				chatLogWasOpen = true
				if debugmode then windower.add_to_chat(207, 'FastTarget - Chat log out of the way !!') end
			end
			
			if player and ((not chatLogWasOpen and info.menu_open) or playerStatus == 1 or player.target_locked == true) then
				
				if find_queue_target_next_id > 0 and S{key_tab, key_f8, settings.custom_left,settings.custom_right,settings.custom_nearest}[dik] then 
					if debugmode then windower.add_to_chat(207, 'FastTarget - Reset last sub-target selection.') end
					find_queue_target_next_id = 0 --Need to reset previous sub-target if we do another one
				end
				
				if not subTargeting and ((S{key_tab,key_f8,settings.custom_left,settings.custom_right,settings.custom_nearest}[dik] and flags == 0) or (dik==key_tab and flags == 1)) then
					subTargeting = true
					
					local target = nil
					local targetIndex = player.target_index
					if targetIndex ~= nil then
						target = windower.ffxi.get_mob_by_index(targetIndex)
					end
					
					--Detect if in combat or nearly just death target
					--local inCombat = playerStatus == 1 or (target and (target.status == 2 or target.status == 3))
					local inCombat = playerStatus == 1
					local targetCommand = '/target'
					if inCombat then
						--Decide if we queue or change to next target
						if settings.use_auto_switch and settings.use_allow_queue and S{key_f8,settings.custom_nearest}[dik] and (target == nil or target.distance:sqrt() < find_max_distance_auto_queue) and is_mob_in_front(target) then
							--Allow new sub-target to be selected and queued for target switch
							find_queue_target_activated = true
						else
							--Allow regular target switch using /attack on a new sub-target
							find_queue_target_activated = false
							targetCommand = '/attack'
						end
					end
					local targetSelection = (settings.use_st_target and not inCombat) and '<st>' or '<stnpc>' --inCombat must enforce <stnpc>
					
					if debugmode then
						if inCombat then
							windower.add_to_chat(207, 'FastTarget - Overriding in combat lock with '..targetCommand..' '..targetSelection)
						elseif player.target_locked then
							windower.add_to_chat(207, 'FastTarget - Overriding target lock with '..targetCommand..' '..targetSelection)
						else
							windower.add_to_chat(207, 'FastTarget - Overriding menu lock with '..targetCommand..' '..targetSelection)
						end
					end
					if chatLogWasOpen then
						--Add small delay to avoid message we can't use this command while chatlog is open
						windower.send_command('@input ;wait 0.1;input '..targetCommand..' '..targetSelection)
					else
						windower.chat.input(targetCommand..' '..targetSelection)
					end
					
					if settings.use_auto_next_st and S{key_f8,settings.custom_nearest}[dik] then
						--Activate autotarget if enable
						find_mobs = get_next_mob()
						findNextTarget()
					elseif settings.use_auto_switch then
						--Activate autoswitch on targetting if enable
						switchNextTarget()
					end
					
					return true
			
				elseif S{key_enter}[dik] then --Enter
					if subTargeting and find_queue_target_activated then
						local currentTarget = windower.ffxi.get_mob_by_target('t')
						local lastSubTarget = windower.ffxi.get_mob_by_target('st','lastst')
						if currentTarget and lastSubTarget and currentTarget.id ~= lastSubTarget.id and is_valid_target(lastSubTarget) then
							find_queue_target_current_id = currentTarget.id
							find_queue_target_next_id = lastSubTarget.id
							--Activate autoswitch on next target if enable
							switchNextTarget()
							if debugmode then windower.add_to_chat(207, 'FastTarget - new subtarget selected for next target '..find_queue_target_next_id) end
						end
					end
					if settings.use_allow_queue then
						--Activate auto mob tracking queue
						trackLastSubTarget()
					end
					
					reset()
				elseif S{key_esc}[dik] then --Esc
					reset()
				end
			
			elseif subTargeting == true and S{key_esc,key_enter}[dik] then
				reset()
			end
		end
    end
end
)


windower.register_event('addon command', function(...)
	local arg = {...}
	if #arg == 1 and arg[1]:lower() == 'bind' then	
		windower.add_to_chat(200, 'FastTarget - Automatic key bind')
		windower.add_to_chat(200, '  Binding custom keys that will be alternatives to the default Tab, Alt-Tab and F8.')
		windower.add_to_chat(200, '  Press to register three custom keys one after then other.')
		windower.add_to_chat(200, 'Start pressing keys now... (Cancel using ESC)')
		windower.add_to_chat(200, '  1) Press key to bind target left (Alt-Tab):')
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
			windower.add_to_chat(200, 'FastTarget - Automatically search for the next, nearest and in front sub-target available using ingame sub-target system (F8). This search will be done by rapidly switching sub-target arrow until one of the best targets is found. This allow to confirm, adjust or cancel sub-target.')
		end
		settings:save()
			
	elseif #arg == 1 and arg[1]:lower() == 'switch' then
		if settings.use_auto_switch == true then
			settings.use_auto_switch = false
			windower.add_to_chat(200, 'FastTarget - Manual confirmation to apply sub-target.')
		else
			settings.use_auto_switch = true
			windower.add_to_chat(200, 'FastTarget - Automatically switch to current or last queued sub-target when current target die.')
		end
		settings:save()
		
	elseif #arg == 1 and arg[1]:lower() == 'queue' then
		if settings.use_allow_queue == true then
			settings.use_allow_queue = false
			windower.add_to_chat(200, 'FastTarget - New sub-target will change target immediately upon confirmation.')
		else
			settings.use_allow_queue = true
			windower.add_to_chat(200, 'FastTarget - New sub-target will be queued and switched to when current combat target die. Queuing only work if current in-combat target is in front and distance is less than '..find_max_distance_auto_queue..' yards. Additionnaly track and queue sub-target made from spell and job ability on a sub-target different than the current one. This option need auto-switch to be activated.')
		end
		settings:save()
		
	elseif #arg == 1 and arg[1]:lower() == 'display' then
		if settings.display_ui == true then
			settings.display_ui = false
			windower.add_to_chat(200, 'FastTarget - Information will not be displayed.')
		else
			settings.display_ui = true
			windower.add_to_chat(200, 'FastTarget - Information will be displayed.')
		end
		displayUI()
		settings:save()

	elseif #arg == 0 or (#arg == 1 and arg[1]:lower() == 'help') then
		windower.add_to_chat(200, 'FastTarget - Allows instant override of target lock, in-combat lock, action menu lock, or chat history lock for faster target switching using Tab, Alt-Tab, and F8 keys. Optional automatic target search and switch using the in-game sub-target function.')
		windower.add_to_chat(200, 'Available Options:')
		windower.add_to_chat(200, '  //ft search - Automatically find next best sub-target when using F8 key '..(settings.use_auto_next_st and '(Enabled)' or '(Disabled)'))
		windower.add_to_chat(200, '  //ft switch - Automatic switch to current/queued sub-target when current target die '..(settings.use_auto_switch and '(Enabled)' or '(Disabled)'))
		windower.add_to_chat(200, '  //ft queue - Queue sub-target using F8 key when in-front and near current target '..((settings.use_auto_switch and settings.use_allow_queue) and '(Enabled)' or '(Disabled)'))
		windower.add_to_chat(200, '  //ft target - Change out-of-combat target selection mode between all or npc '..(settings.use_st_target and '(All)' or '(NPC)'))
		windower.add_to_chat(200, '  //ft display - Toggle display of information '..(settings.display_ui and '(Enabled)' or '(Disabled)'))
		windower.add_to_chat(200, '  //ft bind   - Bind additional Tab, Alt-Tab and F8 custom keys')
		windower.add_to_chat(200, '  //ft unbind - Reset custom key binds')
		windower.add_to_chat(200, '  //ft debug - Toggle debug mode')
		windower.add_to_chat(200, '  //ft help   - Displays this text')
	else
		windower.add_to_chat(167, 'FastTarget - Invalid command. //ft help for valid options.')
	end
end)

