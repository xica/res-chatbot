base_dir = File.expand_path("..", __FILE__)
config_dir = File.join(base_dir, "config")
lib_dir = File.join(base_dir, "lib")

$LOAD_PATH << lib_dir << config_dir

require "slack_bot/jobs"
