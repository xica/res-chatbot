require "securerandom"
require "sidekiq/web"
require_relative "app"

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
  "/" => Sinatra::Application,
  "/z-sidekiq" => Sidekiq::Web
)
