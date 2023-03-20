base_dir = File.expand_path("..", __FILE__)
config_dir = File.join(base_dir, "config")
lib_dir = File.join(base_dir, "lib")

$LOAD_PATH << lib_dir << config_dir

require "securerandom"
require "sidekiq/web"

require "slack_bot/app"

Sidekiq::Web.use(Rack::Auth::Basic) do |user, password|
  [user, password] == [ENV["ADMIN_USER"], ENV["ADMIN_PASSWORD"]]
end

def gen_session_secret
  filename = ".session.key"
  unless File.file?(filename)
    File.write(filename, SecureRandom.hex(32))
  end
  File.read(filename)
end

Sidekiq::Web.use Rack::Session::Cookie, secret: gen_session_secret, same_site: true, max_age: 86400

run Rack::URLMap.new(
  "/" => SlackBot::Application,
  "/z-sidekiq" => Sidekiq::Web
)
