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
_addon.version = '1.9'
_addon.command = 'ft'
_addon.commands = {'help', 'bind', 'reset', 'target', 'debug'}
_addon.language = 'english'

--[[ 
-------------INSTRUCTIONS---------------
* Allow to freely target using default TAB, ALT-TAB, F8 or any other custom keys while in combat or locked to a target. 
* ESC will cancel sub-targetting and still allow quick peak at other mobs around.
* ENTER will select the sub-target and engage right away.
* You can map your own additional custom keys or set them to 0 if not needed.
]]

require('sets')
config = require('config')

default_settings = {}
default_settings.use_st_target = false
default_settings.custom_left = 0 --Default Q (16) - Should Match in-game Misc2-> "Menu/Target Cursor Left" 
default_settings.custom_right = 0 --Default E (18) - Should Match in-game Misc2-> "Menu/Target Cursor Right" 
default_settings.custom_nearest = 0 --Default R (19). Used with Gearswap -> send_command('bind %r setkey f8 down;wait 0.5;setkey f8 up') -- good'old F8 shortcut 
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

playerStatus = -1
chat_log_open = false
chat_log_expanded = false

function reset()
	targeting = false
	playerStatus = -1
	chat_log_open = false
	chat_log_expanded = false
end

windower.register_event('addon command', function(...)

	local arg = {...}
	if #arg > 1 then
		windower.add_to_chat(167, 'FastTarget - Invalid command. //ft help for valid options.')
	
	elseif #arg == 1 and arg[1]:lower() == 'bind' then	
		windower.add_to_chat(200, 'FastTarget - Automatic key bind')
		windower.add_to_chat(200, '  Press to register three custom keys one after then other to match the following: ')
		windower.add_to_chat(200, '  1) Target left (Misc 2 -> Menu/Target Cursor Left)')
		windower.add_to_chat(200, '  2) Target right (Misc 2 -> Menu/Target Cursor Left)')
		windower.add_to_chat(200, '  3) Target nearest NPC (Custom F8 rebind or /targetnpc)')
		windower.add_to_chat(200, '  Once completed they will be saved as an alternative do the default Tab, Alt-Tab and F8.')
		windower.add_to_chat(200, 'Start pressing keys now... (Cancel using ESC)')
		windower.add_to_chat(200, '  1) Press your custom key bind to target left:')
		bindmode = 1
	
	elseif #arg == 1 and arg[1]:lower() == 'reset' then
		settings.custom_left = 0
		settings.custom_right = 0
		settings.custom_nearest = 0
		settings:save()
		windower.add_to_chat(200, 'FastTarget - Custom binding reset')
	
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

	elseif #arg == 0 or (#arg == 1 and arg[1]:lower() == 'help') then
		windower.add_to_chat(200, 'FastTarget - Allows instant override of manual lock, in-combat lock, action menu lock, or chat history lock for faster target switching at any time using the default Tab, Alt-Tab, and F8 keys.')
		windower.add_to_chat(200, 'Available Options:')
		windower.add_to_chat(200, '  //ft target - Change out-of-combat target selection.')
		windower.add_to_chat(200, '  //ft bind   - Bind additional left, right and nearest target custom keys.')
		windower.add_to_chat(200, '  //ft reset  - Reset custom key binds.')
		windower.add_to_chat(200, '  //ft debug - Toggle debug mode.')
		windower.add_to_chat(200, '  //ft help   - Displays this text')
	end
end)

windower.register_event('status change',function(new,old)
    windower.debug('status change '..new)
    if T{2,3,4}:contains(old) or T{2,3,4}:contains(new) then 
		reset()
		return 
	end

	if debugmode then windower.add_to_chat(207, 'FastTarget - Status change detected new='..new..' old='..old) end
	playerStatus = new
end)

windower.register_event('zone change',function(new_id, old_id) 
	targeting = false
	playerStatus = 0
	chat_log_open = false
	chat_log_expanded = false
end)

windower.register_event('keyboard',function(dik,pressed,flags,blocked)
    
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
		
		if bindmode > 0 and not (S{key_shift,key_control,key_alt, key_enter}[dik]) then
			--Bind mode
			if debugmode then windower.add_to_chat(207, 'FastTarget - Bindmode #'..bindmode) end
			
			if dik==key_esc then
				windower.add_to_chat(167, 'FastTarget - Custom binding cancelled !')
				bindmode = 0
			else
				if bindmode == 1 then
					settings.custom_left = dik
					if debugmode then windower.add_to_chat(207, 'FastTarget - Custom target left bound to '..settings.custom_left) end
					windower.add_to_chat(200, '  2) Press your custom key bind to target right:')
					bindmode = bindmode + 1
				elseif bindmode == 2 then
					settings.custom_right = dik
					if debugmode then windower.add_to_chat(207, 'FastTarget - Custom target right bound to '..settings.custom_right) end
					windower.add_to_chat(200, '  3) Press your custom key bind to target nearest:')
					bindmode = bindmode + 1
				elseif bindmode == 3 then
					settings.custom_nearest = dik
					if debugmode then windower.add_to_chat(207, 'FastTarget - Custom target nearest bound to '..settings.custom_nearest) end
					windower.add_to_chat(200, 'FastTarget - Custom binding completed')
					bindmode = 0
					settings:save()
				end
				
			end
	
		elseif S{key_esc,key_enter,key_tab,key_f8,settings.custom_left,settings.custom_right,settings.custom_nearest}[dik] then
			--Target overrde
			local info = windower.ffxi.get_info()
			local player = windower.ffxi.get_player()
			
			if player and playerStatus == -1 then
				--Initial player status after plugin is loaded
				playerStatus = player.status
			end
			
			--Automatic Chatlog away
			local chatLogWasOpen = false
			if chat_log_open and not chat_log_expanded and S{key_tab,key_f8,settings.custom_left,settings.custom_right,settings.custom_nearest}[dik] then
				windower.send_command('setkey escape down;wait 0.5;setkey escape up')
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
							windower.add_to_chat(207, 'FastTarget - Overriding in combat lock with /attack <stnpc>')
						elseif player.target_locked then
							windower.add_to_chat(207, 'FastTarget - Overriding target lock with /target <stnpc>')
						else
							windower.add_to_chat(207, 'FastTarget - Overriding menu lock with /target <stnpc>')
						end
					end
					if chatLogWasOpen then
						--Add small delay to avoid message we can't use this command while chatlog is open
						windower.send_command('@input ;wait 0.1;input '..targetCommand..' '..targetSelection)
					else
						windower.chat.input(targetCommand..' '..targetSelection)
					end
					
					return true
			
				elseif S{key_esc,key_enter}[dik] then --Esc or Enter
					targeting = false
				end
			
			elseif targeting == true and S{key_esc,key_enter}[dik] then
				targeting = false
			end
		end
    end
end
)
