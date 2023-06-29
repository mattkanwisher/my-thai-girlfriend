# brew install youtube-dl

filename = "tmp.mp4"
youtube_url = "https://www.youtube.com/watch?v=4jE02mfSMwI"

system("youtube-dl", "-o", filename, youtube_url)