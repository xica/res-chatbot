require "sidekiq/web"
require_relative "app"

SIdekiq::Web.use(Rack::Auth::Basic) do |user, password|
  [user, password] == [ENV["ADMIN_USER"], ENV["ADMIN_PASSWORD"]]
end

run Rack::URLMap.new(
  "/" => Sinatra::Application,
  "/z-sidekiq" => Sidekiq::Web
)
