# Description
#   A hubot script for reaping messages for slack
#
# Configuration:
#   SLACK_API_TOKEN		- Slack API Token (default. undefined )
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

targetroom = process.env.HUBOT_SLACK_REAPER_CHANNEL
regex = new RegExp(if process.env.HUBOT_SLACK_REAPER_REGEX
                     process.env.HUBOT_SLACK_REAPER_REGEX
                   else
                     ".*")
duration = if process.env.HUBOT_SLACK_REAPER_DURATION
             process.env.HUBOT_SLACK_REAPER_DURATION
           else
             300
apitoken = process.env.SLACK_API_TOKEN

delMessage = (robot, channel, msgid) ->

module.exports = (robot) ->

  data = []
  robot.brain.setAutoSave false
  data = robot.brain.get "hubot-slack-reaper-sumup"
  robot.brain.setAutoSave true

  sumUp = (channel, user) ->
    channel = escape channel
    user = escape user
    # data = robot.brain.get　"hubot-slack-reaper-sumup"
    # -> [ dev_null: { taro: 1, hanako: 2 },
    #      lounge: { taro: 5, hanako: 3 } ]
    if data[channel]
      if data[channel][user]
        data[channel][user]++
      else
        data[channel][user] = 1
    else
      data[channel] = {user: 1}

    robot.brain.set "hubot-slack-reaper-sumup", data
    console.log(data)

  robot.hear regex, (res) ->
    if targetroom
      if res.message.room != targetroom
        return
    msgid = res.message.id
    channel = res.message.rawMessage.channel
    rmjob = ->
      echannel = escape(channel)
      emsgid = escape(msgid)
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
    setTimeout(rmjob, duration * 1000)
    sumUp channel, res.message.user.name.toLowerCase()
