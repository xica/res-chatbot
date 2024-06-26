Rails.application.routes.draw do
  root "blank#index"

  draw :slack_bot
  draw :sidekiq
end
