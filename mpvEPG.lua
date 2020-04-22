--[[
mpvEPG v0.3
lua script for mpv parses XMLTV data and displays scheduling information for current and upcoming broadcast programming.

Dependency: SLAXML (https://github.com/Phrogz/SLAXML)

Copyright © 2020 Peter Žember; MIT Licensed
See https://github.com/dafyk/mpvEPG for details.
--]]
require 'os'
require 'io'
require 'string'

local config = {
            xmltv = os.getenv('HOME')..'/.config/mpv/epg/epg.xml', -- path to XMLTV data
         channels = os.getenv('HOME')..'/.config/mpv/epg/channels.xml', -- path to rytec channels xml

       titleColor = '00FBFE', -- now playing title color
    subtitleColor = '00FBFE', -- now playing short description color
       clockColor = '00FBFE', -- clock color
    upcomingColor = 'FFFFFF', -- upcoming list color
    noEpgMsgColor = '002DD1', -- no EPG message color

        titleSize = '50', -- now playing title font size
     subtitleSize = '40', -- now playing subtitle font size
     progressSize = '40', -- percentual progress font size
 upcomingTimeSize = '25', -- upcoming broadcast time font size
upcomingTitleSize = '35', -- upcoming broadcast title font size

         noEpgMsg = 'No EPG for this channel' -- message displayed when no EPG information found
         duration = 5 -- hide EPG after this time, defined in seconds
}



local ov = mp.create_osd_overlay('ass-events')
local SLAXML = require 'slaxdom'
local xmltv = io.open(config.xmltv):read('*all')
local channels = io.open(config.channels):read('*all')

local xmltvdata = SLAXML:dom(xmltv,{stripWhitespace=true}).root
local channelsdata = SLAXML:dom(channels,{stripWhitespace=true}).root

local assdraw = require 'mp.assdraw'
local ass = assdraw.ass_new()

local timer


--[[ Extract hours and minutes from xmltv timestamp and format to HH:MM
@param time {String} - xmltv timestamp
@returns {String} - time in form HH:MM
--]]
function formatTime(time)
   return string.sub(time, 9, 12):gsub(('.'):rep(2),'%1:'):sub(1,-2)
end

--[[ Calculate tv show progress in percents
@param start {String} - program start, format: YYYYMMDDHHmm 
@param stop {String} - program end, format: YYYYMMDDHHmm 
@param now {String} - actual time, format: YYYYMMDDHHmm 
@returns {String} - Percentage of program progress in two decimal places
--]]
function calculatePercentage(start,stop,now)
  start = tonumber(unixTimestamp(start))
  stop = tonumber(unixTimestamp(stop))
  now = tonumber(unixTimestamp(now))
  return string.format('%0.2f', (now-start)/(stop-start)*100)
end

--[[ Convert YYYYMMDDHHmm string to unix timestamp
@param s {String} - time string, format: YYYYMMDDHHmm 
@returns {String} - unix timestamp
--]]
function unixTimestamp(s)
  p = '(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)'
  year,month,day,hour,min=s:match(p)
  return os.time({day=day,month=month,year=year,hour=hour,min=min})
end

--[[ Draw tv show progress bar and actual system time
@param percent {String} - tv show progress in percent
--]]
function progressBar(percent)
  ass = assdraw.ass_new()
  local w, h = mp.get_osd_size()
  local p = ((w-14)/100)*percent
  if not(w==0) then
    ass:new_event() -- progress bar background
    ass:append('{\\bord2}') -- border size
    ass:append('{\\1c&000000&}') -- background color
    ass:append('{\\3c&000000&}') -- border color
    ass:append('{\\1a&80&}') -- alpha
    ass:pos(7, -5)
    ass:draw_start()
    ass:round_rect_cw(0, 20, w-14, 10,1)
    ass:draw_stop()

    ass:new_event() -- progress bar
    ass:pos(7, -5)
    ass:append('{\\bord0}') -- border size
    ass:append('{\\shad0}') -- shadow
    ass:append('{\\1a&0&}') -- alpha
    ass:append('{\\1c&00FBFE&}') -- background color
    ass:append('{\\3c&000000&}') -- border color
    ass:draw_start()
    ass:rect_cw(1, 19, p, 11)
    ass:draw_stop()

    ass:new_event() -- clock background
    ass:pos(w-128, 21)
    ass:append('{\\bord2}') -- border size
    ass:append('{\\shad0}') -- shadow
    ass:append('{\\1a&80&}') -- alpha
    ass:append('{\\1c&000000&}') -- background color
    ass:append('{\\3c&000000&}') -- border color
    ass:draw_start()
    ass:round_rect_cw(0, 0, 121, 48, 2)
    ass:draw_stop()

    ass:new_event() -- clock
    ass:pos(w-122, 20)
    ass:append('{\\bord2}') -- border size
    ass:append('{\\shad0}') -- shadow
    ass:append('{\\fs50\\b1}') -- font-size
    ass:append('{\\1c&00FBFE&}') -- background color
    ass:append('{\\3c&000000&}') -- border color
    ass:append(os.date('%H:%M'))
  end
end

--[[ Create today TV schedule for channel from xmltv data
@param el {Table} - SLAXML:dom() parsed table
@param channel {String} - channel ID
@returns {String} - TV schedule
--]]
function getEPG(el,channel)
  datelong = os.date('%Y%m%d%H%M')
  date = string.sub(datelong, 1, 8)
  yesterday = os.date('%Y%m%d',os.time()-24*60*60)

  local now = {title='', subtitle=''}
  program = {}
  local progress
  for _,n in ipairs(el.kids) do
    if n.type=='element' and n.name=='programme' then 
      progdate = string.sub(n.attr['start'], 1, 8)
      if n.attr['channel']==channel and (progdate==date or progdate==yesterday) then 
        progstart = string.sub(n.attr['start'], 1, 12)
        progstop = string.sub(n.attr['stop'], 1, 12)
        start = formatTime(n.attr['start'])
        stop = formatTime(n.attr['stop'])
        for _,o in ipairs(n.kids) do
          if o.name=='title' then
            for _,p in ipairs(o.kids) do
              if progstart<=datelong and progstop>=datelong then -- now playing title
                progress = calculatePercentage(progstart,progstop,datelong)
                now.title = string.format('{\\b1\\bord2\\fs%s\\1c&H%s}%s {\\fs%s}(%s%%)\\N',config.titleSize,config.titleColor,p.value,config.progressSize,progress)
                progressBar(progress)
              elseif progstart>datelong then
                program[#program+1] = string.format('{\\b1\\be\\fs%s\\1c&H%s}⦗%s – %s⦘{\\b0\\fs%s} %s\\N',config.upcomingTimeSize,config.upcomingColor,start,stop,config.upcomingTitleSize,p.value)
              end
            end
          elseif o.name=='sub-title' then
            for _,p in ipairs(o.kids) do
              if progstart<=datelong and progstop>=datelong then -- now playing subtitle
                now.subtitle = string.format('{\\bord2\\fs%s\\b1\\i1\\1c&H%s}⦗%s-%s⦘{\\b0}- %s\\N\\N',config.subtitleSize,config.subtitleColor,start,stop,p.value)
              end
            end
          end
        end
      end
    end
  end
  if now.subtitle=='' then now.subtitle = '\\N' end
  table.sort(program)
  table.insert(program,1,now.subtitle)
  table.insert(program,1,now.title)  
  return table.concat(program)
end

--[[ Search for channel ID in rytec channels list xml
@param el {Table} - SLAXML:dom() parsed table
@param channel {String} - bouquet ID
@returns {String} - channel ID
--]]
function getChannelName(el,channel)
  local id
  for _,n in ipairs(el.kids) do
    if n.type=='element' and n.name=='channel' then 
      for _,o in ipairs(n.kids) do
        if o.value==channel then
          id = n.attr['id']
        end
      end
    end
  end
  if id then return id end
end

--[[ Displays today TV schedule
--]]
function showEPG()
  if not(timer==nil) then
    timer:kill()
    timer = nil
  end
  local w, h = mp.get_osd_size()
  local channel = string.match(mp.get_property('stream-open-filename'), '[^/]+$')
  local channelID = getChannelName(channelsdata,channel)
  if not(channelID==nil) then
    local data = getEPG(xmltvdata,channelID)
    if data then
      ov.data = data
    else
      ov.data = string.format('{\\b0\\1c&H%s}%s',config.noEpgMsgColor,config.noEpgMsg)
      ass.text = ''
    end
  else
    ov.data = string.format('{\\b0\\1c&H%s}%s',config.noEpgMsgColor,config.noEpgMsg)
    ass.text = ''
  end
  ov:update()
  mp.set_osd_ass(w, h, ass.text)
  timer = mp.add_timeout(config.duration, function() ov:remove(); mp.set_osd_ass(0, 0, ''); end )
end
 
-- Set key binding.
mp.add_key_binding('h', showEPG)
mp.register_event('file-loaded', showEPG)
