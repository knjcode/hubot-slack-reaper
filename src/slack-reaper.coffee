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
