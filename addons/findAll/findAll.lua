--[[
findAll v1.20131120

Copyright (c) 2013, Giuliano Riccio
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.
* Neither the name of findAll nor the
names of its contributors may be used to endorse or promote products
derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Giuliano Riccio BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

_addon.name    = 'findAll'
_addon.author  = 'Zohno'
_addon.version = '1.20140328'
_addon.command = 'findAll'

require('chat')
require('lists')
require('logger')
require('sets')
require('tables')
require('strings')

json  = require('json')
file  = require('files')
slips = require('slips')

zone_search            = true
first_pass             = true
time_out_offset        = 0
next_sequence_offset   = 0
item_names             = T{}
global_storages        = T{}
storages_path          = 'data/storages.json'
storages_order         = L{'temporary', 'inventory', 'wardrobe', 'safe', 'storage', 'locker', 'satchel', 'sack', 'case'}
storage_slips_order    = L{'slip 01', 'slip 02', 'slip 03', 'slip 04', 'slip 05', 'slip 06', 'slip 07', 'slip 08', 'slip 09', 'slip 10', 'slip 11', 'slip 12', 'slip 13', 'slip 14', 'slip 15', 'slip 16', 'slip 17', 'slip 18'}
merged_storages_orders = L{}:extend(storages_order):extend(storage_slips_order)
resources              = require ('resources').items

function search(query, export)
    update()

    if query:length() == 0 then
        return
    end

    local character_set    = S{}
    local character_filter = S{}
    local terms            = ''

    for _, query_element in ipairs(query) do
        local char = query_element:match('^([:!]%a+)$')
        if char then
            if char:sub(1, 1) == '!' then
                character_filter:add(char:sub(2):lower():gsub("^%l", string.upper))
            else
                character_set:add(char:sub(2):lower():gsub("^%l", string.upper))
            end
        else
            terms = query_element
        end
    end

    if character_set:length() == 0 and terms == '' then
        return
    end

    local new_item_ids = S{}

    for character_name, storages in pairs(global_storages) do
        for storage_name, storage in pairs(storages) do
            if storage_name ~= 'gil' then
                for id, quantity in pairs(storage) do
                    id = tostring(id)

                    if item_names[id] == nil then
                        new_item_ids:add(tostring(id))
                    end
                end
            end
        end
    end

    for i,_ in pairs(new_item_ids) do
        local id = tonumber(i)
	    if (resources[id]) then
            item_names[i] = {
                ['name'] = resources[id].name,
                ['long_name'] = resources[id].name_log
            }
        end
    end

    local results_items = S{}
    local terms_pattern = ''

    if terms ~= '' then
        terms_pattern = terms:escape():gsub('%a', function(char) return string.format("[%s%s]", char:lower(), char:upper()) end)
    end

    for id, names in pairs(item_names) do
        if terms_pattern == '' or item_names[id].name:find(terms_pattern)
            or item_names[id].long_name:find(terms_pattern)
        then
            results_items:add(id)
        end
    end

    log('Searching: '..query:concat(' '))
    
    local no_results   = true
    local sorted_names = global_storages:keyset():sort()
                                                 :reverse()

    if windower.ffxi.get_info().logged_in then
        sorted_names = sorted_names:append(sorted_names:remove(sorted_names:find(windower.ffxi.get_player().name)))
                               :reverse()
    end

    local export_file

    if export ~= nil then
        export_file = io.open(windower.addon_path..'data/'..export, 'w')

        if export_file == nil then
            error('The file "'..export..'" cannot be created.')
        else
            export_file:write('"char";"storage";"item";"quantity"\n')
        end
    end

    for _, character_name in ipairs(sorted_names) do
        if (character_set:length() == 0 or character_set:contains(character_name)) and not character_filter:contains(character_name) then
            local storages = global_storages[character_name]

            for _, storage_name in ipairs(merged_storages_orders) do
                local results = L{}

                if storage_name~= 'gil' and storages[storage_name] ~= nil then
                    for id, quantity in pairs(storages[storage_name]) do
                        if results_items:contains(id) then
                            if terms_pattern ~= '' then
                                results:append(
                                    (character_name..'/'..storage_name..':'):color(259)..' '..
                                    item_names[id].name:gsub('('..terms_pattern..')', ('%1'):color(258))..
                                    (item_names[id].name:match(terms_pattern) and '' or ' ['..item_names[id].long_name:gsub('('..terms_pattern..')', ('%1'):color(258))..']')..
                                    (quantity > 1 and ' '..('('..quantity..')'):color(259) or '')
                                )
                            else
                                results:append(
                                    (character_name..'/'..storage_name..':'):color(259)..' '..item_names[id].name..
                                    (quantity > 1 and ' '..('('..quantity..')'):color(259) or '')
                                )
                            end

                            if export_file ~= nil then
                                export_file:write('"'..character_name..'";"'..storage_name..'";"'..item_names[id].name..'";"'..quantity..'"\n')
                            end

                            no_results = false
                        end
                    end

                    results:sort()

                    for i, result in ipairs(results) do
                        log(result)
                    end
                end
            end
        end
    end

    if export_file ~= nil then
        export_file:close()
        log('The results have been saved to "'..export..'"')
    end

    if no_results then
        if terms ~= '' then
            if character_set:length() == 0 and character_filter:length() == 0 then
                log('You have no items that match \''..terms..'\'.')
            else
                log('You have no items that match \''..terms..'\' on the specified characters.')
            end
        else
            log('You have no items on the specified characters.')
        end
    end
end

function get_storages()
    local items    = windower.ffxi.get_items()
    local storages = {}

    if not items then
        return false
    end

    storages.gil = items.gil

    for _, storage_name in ipairs(storages_order) do
        storages[storage_name] = T{}

        for _, data in ipairs(items[storage_name]) do
            local id = tostring(data.id)

            if id ~= "0" then
                if storages[storage_name][id] == nil then
                    storages[storage_name][id] = data.count
                else
                    storages[storage_name][id] = storages[storage_name][id] + data.count
                end
            end
        end
    end

    local slip_storages = slips.get_player_items()

    for _, slip_id in ipairs(slips.storages) do
        local slip_name     = 'slip '..tostring(slips.get_slip_number_by_id(slip_id)):lpad('0', 2)
        storages[slip_name] = T{}

        for _, id in ipairs(slip_storages[slip_id]) do
            storages[slip_name][tostring(id)] = 1
        end
    end

    return storages
end

function update()
    if not windower.ffxi.get_info().logged_in then
        print('You have to be logged in to use this addon.')
        return false
    end

    if zone_search == false then
        notice('findAll has not detected a fully loaded inventory yet.')
        return false
	end

    local player_name   = windower.ffxi.get_player().name
    local storages_file = file.new(storages_path)

    if not storages_file:exists() then
        storages_file:create()
    end

    global_storages = json.read(storages_file)

    if global_storages == nil then
        global_storages = T{}
    end
	
	local temp_storages = get_storages()

	if temp_storages then
		global_storages[player_name] = temp_storages
	else
		return false
	end

    -- build json string
    local characters_json = L{}

    for character_name, storages in pairs(global_storages) do
        local storages_json = L{}

        for storage_name, storage in pairs(storages) do
            if storage_name == 'gil' then
                storages_json:append('"'..storage_name..'":'..storage)
            elseif storage_name ~= 'temporary' and not storage_name:match('^slip') then
                local items_json = L{}

                for id, quantity in pairs(storage) do
                    items_json:append('"'..id..'":'..quantity)
                end

                storages_json:append('"'..storage_name..'":{'..items_json:concat(',')..'}')
            end
        end

        characters_json:append('"'..character_name..'":{'..storages_json:concat(',')..'}')
    end

    storages_file:write('{'..characters_json:concat(',\n')..'}')

    collectgarbage()

    return true
end

windower.register_event('load', update:cond(function() return windower.ffxi.get_info().logged_in end))

windower.register_event('incoming chunk', function(id,original,modified,injected,blocked)
    local seq = original:byte(4)*256+original:byte(3)
	if (next_sequence and seq + next_sequence_offset >= next_sequence) or (time_out and seq + time_out_offset >= time_out) then
        zone_search = true
		update()
		next_sequence = nil
        time_out = nil
        sequence_offset = 0
	end
	
	if id == 0x00A then -- First packet of a new zone
		zone_search = false
        time_out = seq+33
        if time_out < time_out%0x100 then
            time_out_offset = 256
        end
        
--	elseif id == 0x01D then
	-- This packet indicates that the temporary item structure should be copied over to
	-- the real item structure, accessed with get_items(). Thus we wait one packet and
	-- then trigger an update.
--        zone_search = true
--		next_sequence = seq+128
--        if next_sequence < next_sequence%0x100 then
--            next_sequence_offset = 256
--        end
    elseif (id == 0x1E or id == 0x1F or id == 0x20) and zone_search then
    -- Inventory Finished packets aren't sent for trades and such, so this is more
    -- of a catch-all approach. There is a subtantial delay to avoid spam writing.
        next_sequence = seq+128
        if next_sequence < next_sequence%0x100 then
            next_sequence_offset = 256
        end
	end
end)

windower.register_event('ipc message', function(str)
    if str == 'findAll update' then
        update()
    end
end)

windower.register_event('addon command', function(...)
    if first_pass then
        first_pass = false
        windower.send_ipc_message('findAll update')
        windower.send_command('wait 0.05;findall '..table.concat({...},' '))
    else
        first_pass = true
        local params = L{...}
        local query  = L{}
        local export = nil

        while params:length() > 0 and params[1]:match('^[:!]%a+$') do
            query:append(params:remove(1))
        end

        if params:length() > 0 then
            export = params[params:length()]:match('^--export=(.+)$') or params[params:length()]:match('^-e(.+)$')

            if export ~= nil then
                export = export:gsub('%.csv$', '')..'.csv'

                params:remove(params:length())

                if export:match('['..('\\/:*?"<>|'):escape()..']') then
                    export = nil

                    error('The filename cannot contain any of the following characters: \\ / : * ? " < > |')
                end
            end

            query:append(params:concat(' '))
        end
        
        search(query, export)
    end
end)
