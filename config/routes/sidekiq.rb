require "sidekiq/web"

Sidekiq::Web.use(Rack::Auth::Basic) do |user, password|
  [user, password] == [ENV["ADMIN_USER"], ENV["ADMIN_PASSWORD"]]
end

mount Sidekiq::Web, at: "z-sidekiq"
