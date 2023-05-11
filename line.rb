# app.rb
require 'sinatra'
require 'line/bot'
require "awesome_print"
require 'sinatra/reloader'
require "openai"
require 'open-uri'

BASE_URL = ENV["BASE_URL"]

GPT_MODEL = "gpt-3.5-turbo" # "gpt-4"
#GPT_MODEL= "ggml-gpt4all-j"
MODEL_WHISPER="whisper-1"
#MODEL_WHISPER="ggml-large.bin"

set :public_folder, Proc.new { File.join(root, "static") }

HT_API_KEY=ENV["HT_API_KEY"]
HT_USERNAME=ENV["HT_USERNAME"]
HT_VOICE="th-TH-PremwadeeNeural"


OpenAI.configure do |config|
    config.access_token = ENV.fetch("OPENAI_API_KEY")
#    config.uri_base = "http://localhost:8080/" 
    config.request_timeout = 240 # Optional
#    config.organization_id = ENV.fetch("OPENAI_ORGANIZATION_ID") # Optional.
end

oaclient = OpenAI::Client.new

ap oaclient.models.list
#ap oaclient.models.retrieve(id: "ggml-gpt4all-j")
@messages = [] #TODO make this multiuser
@first_time = true

def call_openai_llm(oaclient, content) 
   # oaclient = OpenAI::Client.new(access_token: OPENAI_API_KEY)
    @messages = [] #TODO make this multiuser
    @first_time = true
  
    if @first_time == false
      @messages << { role: "user", content: content }
    else 
      @messages << { role: "user", content: "We are on a date in Bangkok Thailand. I will ask you questions as a man and you response as a woman. Please respond in Thai\n\nQ: #{content}"}
    end
    @first_time = false
  
    response = oaclient.chat(
      parameters: {
          model: GPT_MODEL, # Required.
          messages: @messages, # Required.
          temperature: 0.7,
      })
    puts response.inspect
    response_text = response.dig("choices", 0, "message", "content")
    if !response_text.nil? && response_text.length > 2
      @messages << { role: "assistant", content: response_text }
    end
    return response_text #.split("A:")[1]
  end

def convert(htvoice, content)
    url = URI("https://play.ht/api/v1/convert")
  
    payload = {
    #  "voice": "en-US-MichelleNeural",
      "voice": htvoice, #"th-TH-ThanwaNeural",
      "speed": "0.3",
      "content": [
        content #   "either pass content s an array of strings , or ssml , but not both"
      ],
      "title": "Testing thai language"
    }.to_json
  
    headers = {
        'Authorization': HT_API_KEY,
        'X-User-ID': HT_USERNAME,
        'Content-Type': 'application/json'
    }
  
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
  
    request = Net::HTTP::Post.new(url, headers)
    request.body = payload
  
    puts "request--"
    puts request.inspect 
  
    response = http.request(request)
    puts response.body
    data = JSON.parse(response.body)
    puts data
    return data["transcriptionId"]
end
  
def download_ht(transcriptionID, tries=0)
    audioDuration = 0
    if tries == 5 
        return nil
    end
    url = URI("https://play.ht/api/v1/articleStatus?transcriptionId=#{transcriptionID}")
  
  
    headers = {
      'Authorization': HT_API_KEY,
      'X-User-ID': HT_USERNAME,
      'Content-Type': 'application/json'
    }
  
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
  
    request = Net::HTTP::Get.new(url, headers)
    #request.body = payload
  
    response = http.request(request)
    puts response.body
  
    #parse and get the url
    data = JSON.parse(response.body)
    puts data
  
    converted = data["converted"]
    if converted == false
      puts "not converted yet"
      sleep 5 
      tries = tries +1
      return download_ht(transcriptionID, tries)
    end
    turl = data["audioUrl"]
    audio_duration = data["audioDuration"] * 1000
    puts "audio_duration- #{audio_duration}"

    #download file
    url = URI(turl)
    downloaded_file = url.open()
    tempfile = Tempfile.new(['prefix', '.mp3'])
    tempfile.write(downloaded_file.read)
  
    downloaded_file.close
    tempfile.close
    tempfile.open
  
    tempfile_path = tempfile.path
    puts tempfile_path
    tempfile.close
    #tempfile.unlink # in theory this deletes the file, we should do when program is done
  
    return tempfile_path, audio_duration
  end

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
        tf = Tempfile.new([ 'line', '.m4a' ])
        tf.write(response.body)
        ap tf.path  #Sweet we have the audio
        #system "afplay #{tf.path}"

        #tmp_voice_file2 = "recording2.wav" #todo make a tempfile

        #decode audio format
        # system "ffmpeg -y -i #{tf.path} -ar 16k #{tmp_voice_file2}"

        #send to whisper
        response = oaclient.transcribe(
            parameters: {
                model: MODEL_WHISPER,
                file: File.open(tf.path, "rb"),
            })
        whisper_text =  response["text"]
        puts "Whisper text - #{whisper_text}"

        #send to openAI
        #1. Call OPENAI API to get the text for conversation
        response_text = call_openai_llm(oaclient, whisper_text)
        puts "response_text- #{response_text}"

        puts "-----"
        puts @messages
        puts "-----"
        
        #convert response to audio

        #2. Call HT API to convert text to speech
        transcriptionID = convert(HT_VOICE, response_text)
        puts "transcriptionID-#{transcriptionID}"
        filename, audio_duration = download_ht(transcriptionID)
        puts "filename-#{filename}"
        FileUtils.cp(filename, "static/files/tmp.mp3")

        output_audio = "#{BASE_URL}/files/tmp.mp3"
#        output_audio = "https://play.ht/api/v1/articleStatus?transcriptionId=#{transcriptionID}"

        #send audio to line

        message = {
            type: 'audio',
            originalContentUrl: output_audio,
            duration: audio_duration.to_i.to_s
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