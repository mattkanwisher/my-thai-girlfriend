# app.rb
require 'sinatra'
require 'line/bot'
require "awesome_print"
require 'sinatra/reloader'

BASE_URL = "https://c797-2405-9800-b650-6c84-55d5-4506-fcce-3a52.ap.ngrok.io"

set :public_folder, Proc.new { File.join(root, "static") }

def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_id = ENV["LINE_CHANNEL_ID"]
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

post '/callback' do
  body = request.body.read

  signature = request.env['HTTP_X_LINE_SIGNATURE']
  unless client.validate_signature(body, signature)
    error 400 do 'Bad Request' end
  end

  events = client.parse_events_from(body)
  events.each do |event|
    ap event
    case event
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Audio 
        puts "weeeeee audio"
        response = client.get_message_content(event.message['id'])
        ap response
        tf = Tempfile.open("content")
        tf.write(response.body)
        ap tf.path  #Sweet we have the audio


        #TODO decode audio format
        #send to whisper
        #send to openAI
        #convert response to audio
        #send audio to line

        message = {
            type: 'audio',
            originalContentUrl: "#{BASE_URL}/files/example.m4a",
            duration: 60000
          }
   
        client.reply_message(event['replyToken'], message)
      when Line::Bot::Event::MessageType::Text
        message = {
          type: 'text',
          text: event.message['text']
        }
        client.reply_message(event['replyToken'], message)
      when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
        response = client.get_message_content(event.message['id'])
        tf = Tempfile.open("content")
        tf.write(response.body)
      end
    end
  end

  # Don't forget to return a successful response
  "OK"
end