# Description
#   A hubot script for reaping messages for slack
#
# Configuration:
#   SLACK_API_TOKEN		- Slack API Token (default. undefined )
#   HUBOT_SLACK_REAPER_SETTINGS - Set JSON file url includes target channels,
#             patterns, and durations as follows:
#             { "channelRegexp": { "patternRegexp": duration } }
#
#   Unless set HUBOT_SLACK_REAPER_SETTINGS, use configuration as below
#   HUBOT_SLACK_REAPER_CHANNEL	- Target channel
#   			 	  (default. undefined i.e. all channels)
#   HUBOT_SLACK_REAPER_REGEX	- Target pattern (default. ".*")
#   HUBOT_SLACK_REAPER_DURATION	- Duration to reap in seconds (default. 300)
#
# Commands:
#   N/A
#
# Notes:
#   This hubot script removes every message, matched $HUBOT_SLACK_REAPER_REGEX,
#   posted into $HUBOT_SLACK_REAPER_CHANNEL in $HUBOT_SLACK_REAPER_DURATION
#   seconds after the post.
#
# Author:
#   Katsuyuki Tateishi <kt@wheel.jp>

cron = require('cron').CronJob
time = require 'time'

module.exports = (robot) ->

  settings = undefined
  if process.env.HUBOT_SLACK_REAPER_SETTINGS
    url = process.env.HUBOT_SLACK_REAPER_SETTINGS
    robot.logger.info("Read json from:" + url)
    robot.http(url)
      .get() (err, resp, body) ->
        try
          settings = JSON.parse body
          robot.logger.info("settings:" + JSON.stringify settings)
        catch error
          robot.logger.error("JSON parse error")
  else
    targetroom = process.env.HUBOT_SLACK_REAPER_CHANNEL ? "^dev_null$"
    regex = process.env.HUBOT_SLACK_REAPER_REGEX ? ".*"
    duration = process.env.HUBOT_SLACK_REAPER_DURATION ? 300
    try
      settings = JSON.parse "{ \"#{targetroom}\": { \"#{regex}\": #{duration} } }"
      robot.logger.info("settings:" + JSON.stringify settings)
    catch error
      robot.logger.error("JSON parse error")

  apitoken = process.env.SLACK_API_TOKEN

  data = {}
  room = {}
  loaded = false

  robot.brain.on 'loaded', ->
    try
      data = JSON.parse robot.brain.get "hubot-slack-reaper-sumup"
      room = JSON.parse robot.brain.get "hubot-slack-reaper-room"
    catch e
      console.log 'JSON parse error'
    loaded = true

  robot.hear /.*/, (res) ->
    if not isInChannel(res.message.room)
      return

    delDur = getDeleteDuration res.message.room, res.message.text

    if delDur isnt Infinity
      rmjob =  ->
        echannel = escape(res.message.rawMessage.channel)
        emsgid = escape(res.message.id)
        eapitoken = escape(apitoken)
        robot.http("https://slack.com/api/chat.delete?token=#{eapitoken}&ts=#{emsgid}&channel=#{echannel}")
          .get() (err, resp, body) ->
            try
              json = JSON.parse(body)
              if json.ok
                robot.logger.info("Removed #{res.message.user.name}'s message \"#{res.message.text}\" in #{res.message.room}")
              else
                robot.logger.error("Failed to remove message")
            catch error
              robot.logger.error("Failed to request removing message #{msgid} in #{channel} (reason: #{error})")
      setTimeout(rmjob, delDur * 1000)
      sumUp res.message.room, res.message.user.name.toLowerCase()

  robot.hear /^score$/, (res) ->
    if not isInChannel(res.message.room)
      return
    res.send score(res.message.room)

  robot.hear /^settings$/, (res) ->
    res.send "```" + JSON.stringify(settings) + "```"

  robot.hear /^report (enable|disable|list)$/, (res) ->
    if res.match[1] is "enable" or res.match[1] is "disable"
      addRoom(res.message.room, res.match[1])
      msg = res.match[1] + " score report of " + res.message.room
      robot.logger.info msg
      res.send msg
      enableReport()
    else if res.match[1] is "list"
      res.send JSON.stringify room

  score = (channel) ->
    # sort by deletions
    z = []
    for k,v of data[channel]
      z.push([k,v])
    z.sort( (a,b) -> b[1] - a[1] )

    # return score report
    if z.length > 0
      msgs = [ "Deleted ranking of " + channel ]
      for user in z
        msgs.push(user[0]+':'+user[1])
      return msgs.join('\n')
    return ""

  sumUp = (channel, user) ->
    channel = escape channel
    user = escape user
    # data = robot.brain.get　"hubot-slack-reaper-sumup"
    # -> { dev_null: { taro: 1, hanako: 2 },
    #      lounge: { taro: 5, hanako: 3 } }
    if !data[channel]
      data[channel] = {}
    if !data[channel][user]
      data[channel][user] = 0
    data[channel][user]++
    console.log data

    # robot.brain.set wait until loaded avoid destruction of data
    if loaded
      robot.brain.set "hubot-slack-reaper-sumup", JSON.stringify data

  isInChannel = (channel) ->
    for roomRegExp, _ of settings
      if RegExp(roomRegExp).test(channel)
        return true
    return false

  getDeleteDuration = (channel, msg) ->
    durations = []
    for roomRegExp, patternRegExps of settings
      for msgRegExp, duration of patternRegExps
        if RegExp(roomRegExp).test(channel)
          if RegExp(msgRegExp).test(msg)
            durations.push(duration)
    return Math.min.apply 0, durations

  addRoom = (channel, setting) ->
    channel = escape channel
    # room = robot.brain.get　"hubot-slack-reaper-room"
    # -> { dev_null: enable,
    #      lounge: disable }
    room[channel] = setting

    # robot.brain.set wait until loaded avoid destruction of data
    if loaded
      robot.brain.set "hubot-slack-reaper-room", JSON.stringify room

  report = ""
  enableReport = ->
    report = new cron('0 55 12 * * *', () ->
      for channel, setting of room
        if setting is "enable"
          robot.send { room: channel }, score(channel)
    )
    report.start()
  enableReport()
