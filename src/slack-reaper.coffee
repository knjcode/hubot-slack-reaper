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
#   HUBOT_SLACK_REAPER_TIMEZONE - Timezone (default. "Asia/Tokyo")
#   HUBOT_SLACK_REAPER_DOBACKUP - Backup data on daily or not (default. "false")
#   HUBOT_SLACK_REAPER_BACKUPTIME - Time of daily backup (default. "00:00")
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

cronJob = require('cron').CronJob
time = require 'time'
cloneDeep = require 'lodash.clonedeep'

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
          robot.logger.error("JSON parse error at load json")
  else
    targetroom = process.env.HUBOT_SLACK_REAPER_CHANNEL ? "^dev_null$"
    regex = process.env.HUBOT_SLACK_REAPER_REGEX ? ".*"
    duration = process.env.HUBOT_SLACK_REAPER_DURATION ? 300
    try
      settings = JSON.parse "{ \"#{targetroom}\": { \"#{regex}\": #{duration} } }"
      robot.logger.info("settings:" + JSON.stringify settings)
    catch error
      robot.logger.error("JSON parse error at load json")

  apitoken = process.env.SLACK_API_TOKEN
  timezone = process.env.HUBOT_SLACK_REAPER_TIMEZONE ? "Asia/Tokyo"
  doBackup = process.env.HUBOT_SLACK_REAPER_DOBACKUP ? false
  backupTime = process.env.HUBOT_SLACK_REAPER_BACKUPTIME ? "00:00"

  data = {}
  latestData = {}
  room = {}
  report = []
  backupJob = {}
  loaded = false

  robot.brain.on 'loaded', ->
    # hubot-slack-reaper-sumup:          current sum-up data
    #   -> { dev_null: { taro: 1, hanako: 2 },
    #        lounge: { taro: 5, hanako: 3 } }
    #
    # hubot-slack-reaper-sumup-latest:   latest sum-up data
    #   Same format as hubot-slack-reaper-sumup
    #   When hubot report sum-up data and HUBOT_SLACK_REAPER_DOBACKUP is true,
    #   set current sum-up to latest
    #
    # hubot-slack-reaper-sumup-YYYYMMDD: daily backup of sum-up data
    #   Same format as hubot-slack-reaper-sumup
    #   Backup data at the time of HUBOT_SLACK_REAPER_BACKUPTIME
    #   YYYYMMDD is backup date
    #
    # hubot-slack-reaper-room:           Whether report sum-up data or not
    #   Set channel name with cron pattern
    #   -> { dev_null: "0 9,21 * * *",
    #        lounge: "disable" }
    if !loaded
      try
        data = JSON.parse robot.brain.get "hubot-slack-reaper-sumup"
        room = JSON.parse robot.brain.get "hubot-slack-reaper-room"
      catch error
        robot.logger.error("JSON parse error at robot.brain.get")
      latestData = cloneDeep data
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
              robot.logger.error("Failed to request removing message #{emsgid} in #{echannel} (reason: #{error})")
      setTimeout(rmjob, delDur * 1000)
      sumUp res.message.room, res.message.user.name.toLowerCase()

  robot.hear /^score$/, (res) ->
    if not isInChannel(res.message.room)
      return
    res.send score(res.message.room)

  robot.hear /^settings$/, (res) ->
    msgs = []
    msgs.push "```" + JSON.stringify(settings) + "```"
    msgs.push "timezone:" + timezone
    msgs.push "doBackup:" + doBackup
    msgs.push "backupTime:" + backupTime
    res.send msgs.join('\n')

  robot.hear /^report (enable|disable|list) *(\S+ \S+ \S+ \S+ \S+)*$/, (res) ->
    if res.match[1] is "enable" or res.match[1] is "disable"
      if addRoom(res.message.room, res.match[1], res.match[2])
        msg = res.match[1] + " score report of " + res.message.room + " " + res.match[2]
        robot.logger.info(msg)
        res.send msg
        enableReport()
      else
        res.send "Failed to change cron setting"
    else if res.match[1] is "list"
      res.send JSON.stringify room

  score = (channel) ->
    # diff = data[channel] - latestData[channel]
    diff = {}
    for name, num of data[channel]
      if (num - latestData[channel][name]) > 0
        diff[name] = num - latestData[channel][name]
    # update latestData
    latestData = cloneDeep data

    # sort by deletions of data
    z = []
    for k,v of diff
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
    if !data
      data = {}
    if !data[channel]
      data[channel] = {}
    if !data[channel][user]
      data[channel][user] = 0
    data[channel][user]++
    robot.logger.info(data)

    # wait robot.brain.set until loaded avoid destruction of data
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

  addRoom = (channel, setting, cron) ->
    channel = escape channel
    if !room
      room = {}
    if setting is "enable"
      # check cron pattern
      try
        new cronJob "0 " + cron, () ->
      catch error
        robot.logger.error("Invalid cron pattern:" + cron)
        return false
      room[channel] = cron
    else
      room[channel] = "disable"

    # wait robot.brain.set until loaded avoid destruction of data
    if loaded
      robot.brain.set "hubot-slack-reaper-room", JSON.stringify room
    return true

  enableReport = ->
    for job in report
      job.stop()
    repot = []

    if loaded
      for channel, setting of room
        if setting isnt "disable"
          report[report.length] = new cronJob "0 " + setting, () ->
            robot.send { room: channel }, score(channel)
          , null, true, timezone
  enableReport()

  dailyBackup = ->
    if doBackup isnt "false"
      [hour, min] = backupTime.split(":")
      cron = "0 " + min + " " + hour + " * * *"
      d = new Date()
      YYYY = d.getFullYear()
      MM = (d.getMonth() + 101).toString().slice(1)
      DD = (d.getDate() + 100).toString().slice(1)
      backupKey = "hubot-slack-reaper-sumup-"+YYYY+MM+DD

      backupJob = new cronJob cron, () ->
        if loaded
          robot.brain.set backupKey, data
          latestData = cloneDeep data
          robot.logger.info("Daily backup")
      , null, true, timezone
  dailyBackup()
